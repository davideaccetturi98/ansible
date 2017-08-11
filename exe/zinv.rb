#!/usr/bin/env ruby
require 'zabbixapi'
require 'json'
require 'trollop'
require 'pry'
require 'awesome_print'
require 'set'
require 'yaml'

# This list forms the basis for the collection of hosts and
# templates included in inventory.  Any template directly or
# indirectly derived from these will be included.  Any host
# using any of the included templates will be included.
roottemplatenames = [
                'Template OS Linux',
                'Template OS Linux Active',
                'Template SNMP OS Linux'
]
# Assign a comma separated list of host names to this before running
# ansible-playbook to have hosts not yet in zabbix listed in inventory
runtimehostvar = 'ZINV_ADD_HOSTS'

opts = Trollop::options do
    opt :list, "List entire inventory" # required by ansible
    opt :host, "List a single host", :type => :string  # required by ansible
    opt :debug, "Debugging verbosity"
    opt :groups, "Dump groups list"
    opt :templates, "Dump templates list"
end

# Generate an in-memory host group with the comma delim list in this env var
if ENV[runtimehostvar]
    newhostnamelist = ENV[runtimehostvar].split(',')
else
    newhostnamelist = Array.new
end

# This is here just to satisfy the spec.  This script generates a top level
# _meta element which deprecates the requirement so this is basically
# dead code.
if opts[:host]
    puts Hash.new.to_json
    exit
end

# Connect to zabbix.
zbx = ZabbixApi.connect(
  :url => "#{ENV['ZINV_ZABBIX_URL']}/api_jsonrpc.php",
  :user => ENV['ZINV_ZABBIX_USER'],
  :password => ENV['ZINV_ZABBIX_PASS'],
  :debug => opts[:debug]
)


# Get all the root template objects
roottemplates = zbx.query(
    :method => 'template.get',
    :params => {
        :filter => {
            :host =>  roottemplatenames
        }
    }
)


ansibletemplates = roottemplates # This list is used by host gathering logic later on
ansibletemplategroups = Hash.new # This holds hosts-by-template - rendered as inventory later
prevchunk = roottemplates # this is for the "walking the tree" logic

# Set up template groups for the root templates
prevchunk.each {|template|
    name = template['name'].gsub(/[ ]/,'_')
    if not ansibletemplategroups.has_key?(name)
        ansibletemplategroups[name] = {'hosts' => Set.new}
    end
}

# Find all templates that derive from the root ones, adding to ansibletemplates
# and ansibletemplategroups as we go
begin
    nextchunk = zbx.query(
        :method => 'template.get',
        :params => {
            :parentTemplateids => prevchunk.collect {|each| each['templateid']}
        }
    )
    nextchunk.each {|template|
        name = template['name'].gsub(/[ ]/,'_')
        if not ansibletemplategroups.has_key?(name)
            ansibletemplategroups[name] = {'hosts' => Set.new}
        end
    }

    if nextchunk.size > 0
        ansibletemplates += nextchunk
        prevchunk = nextchunk
    end
end while nextchunk.size > 0

# Also fudge up a container for all hosts. Probably not necessary as ansible does this
# for us
ansiblehostgroups = {'All_Hosts' => {'hosts' => Set.new}}
# And fudge up a group for whatever host names came at us from the environment variable above
ansiblehostgroups['New_Hosts'] = {'hosts' => newhostnamelist}

# This has will hold host variables from the notes field in zabbix's inventory for a host.
# We render this under the _meta top level entity below. By doing this we force
# ansible to *not* call --host <hostname> a gillion times, which saves a lot of time & cpu
metadata = Hash.new


# Gather all the hosts that use the templates we've collected.  We'll put them in
# two types of hashes: host group hashes and template group hashes.
zbx.hostgroups.all.each { |name,id|
    hostlist = Array.new
    # Gather hosts using our templates, ensuring we also grab inventory for this host
    hosts = zbx.query(
        :method => 'host.get',
        :params => {
            :groupids => [id],
            :templateids => ansibletemplates.collect {|each| each['templateid']},
            :selectParentTemplates => [
                'name'
            ],
            :selectInventory => 'extend'
        }
    )

    # For each host we've collected, add it to each group it belongs in (both host and template),
    # but only if its inclusion in those groups is not overridded by the string DONOTMANAGE
    # in the host's description field.
    hosts.each { |host|
        # You can put the string DONOTMANAGE anywhere in the zabbix host description
        # If you do that the node in question will be excluded from inventory
        if host['description']  !~ /DONOTMANAGE/
            hostlist.push(host['host'])
            host['parentTemplates'].each { |template|
                templatename = template['name'].gsub(/[ ]/,'_')
                if ansibletemplategroups.has_key?(templatename)
                    ansibletemplategroups[templatename]['hosts'].add(host['name'])
                end
            }
            # If you need to define host variables, in the zabbix host definition select "Inventory" and put yaml in the Notes field.
            # See the host "speedtest" for an example.  First line should be '---', then each line after is "key: value"
	    # e.g.:
            # ---
            # ereiamjh: The ghost in the machine
            # youshouldwatch: Brazil
            #
            if host.has_key?('inventory') and host['inventory'].class == Hash and host['inventory'].has_key?('notes') and host['inventory']['notes'].size > 0
                begin
                    metadata[host['name']] = YAML.load(host['inventory']['notes'])
                rescue Exception => e
                    puts "Error parsing inventory notes field for host #{host['name']} - SKIPPING"
                    ap e
                end
            end

        end
    }

    if hostlist.size > 0
        ansiblehostgroups[name.gsub(/[ ]/,'_')] = {'hosts'=>hostlist}
        ansiblehostgroups['All_Hosts']['hosts'].merge(hostlist) # probably don't need this
    end
}

# These are just for more informative dumps...
hostgroupcount = ansiblehostgroups.keys.size
if opts[:groups]
    puts ansiblehostgroups.keys.sort.join("\n")
end
if opts[:templates]
    puts ansibletemplategroups.keys.sort.join("\n")
end
templategroupcount = ansibletemplategroups.keys.size
ansiblehostgroups['All_Hosts']['hosts'] = ansiblehostgroups['All_Hosts']['hosts'].to_a

# Here we add the top level _meta element containing whatever host variables we might have 
# defined in zabbix.  This really *needs* to be here; minus this performance is just awful.
ansiblehostgroups['_meta'] = { 'hostvars' => metadata }
ansibletemplategroups.each { |k,v| 
    v['hosts'] = v['hosts'].to_a
    if v['hosts'].size > 0
    	ansiblehostgroups[k] = v
    end
}
if opts[:list]  # This is the final output to ansible - the inventory
    puts ansiblehostgroups.to_json
elsif not (opts[:groups] or opts[:templates]) # informative dump
    ap ansiblehostgroups
    puts "Root templates #{roottemplatenames.join(',')}"
    puts "#{hostgroupcount} host groups, #{templategroupcount} template groups"
    puts "#{ansiblehostgroups['All_Hosts']['hosts'].size} hosts total"
end
