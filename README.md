# Zinv

zinv.rb generates a dynamic inventory structure for Ansible based on your Zabbix installation's data.  It generates groups based on both host groups and templates by collecting all hosts that use templates directly or indirectly derived from a template list you provide in an environment variable.  It also provides a small "hook" for the addition of hosts that are not yet defined in Zabbix.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'zinv'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install zinv

## Usage

```
$ zinv.rb --help
Options:
  -l, --list         List entire inventory (Ansible convention)
  -h, --host=<s>     List a single host (Ansible convention)
  -d, --debug        Debugging verbosity
  -g, --groups       Dump groups list
  -t, --templates    Dump templates list
  -e, --help         Show this message
```

To use zinv.rb you must (by one of the several methods available) tell Ansible to use zinv.rb as its inventory.   Having done that, define the following environment variables for zinv.rb to work properly:

* ZINV_ZABBIX_URL = your zabbix web interface URL
* ZINV_ZABBIX_USER = user to log into zabbix as
* ZINV_ZABBIX_PASS = password for that user


zinv.rb by default uses the following templates as its "root" ones:

* Template OS Linux
* Template OS Linux Active
* Template SNMP OS Linux

You can override this by setting the following:

* ZINV_ROOT_TEMPLATES = comma separated list of 'root' templates to seed template tree generation (optional)

You can insert hosts into the inventory "manually" by setting the following:

* ZINV_ADD_HOSTS = comma separated list of host names to inject into the inventory under group New_Hosts

In all cases, zinv.rb presumes that the host names it's getting from zabbix (or you, in the case of ZINV_ADD_HOSTS) are resolvable by the host you're running ansible on.  Which is to say if you have a host called myhost1, you should be able to ping myhost1 on the ansible machine.  The implication is that you've either defined all your host names as fqdns in Zabbix, or you've set up your resolver search list properly.


zinv overloads a couple of the fields in a host definition:

You can place the string DONOTMANAGE anywhere in a host's Description field to force zinv to ignore it. If zinv finds DONOTMANAGE in the description, it omits that host from the inventory altogether.

You can define host vars in the host's inventory's Notes field.  Put yaml in it like:

```yaml
---
ereiamjh: The ghost in the machine
kilroy: was here
```

Variables defined in this way will be available to to ansible when it processes the host in question.

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/svdasein/zinv. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

