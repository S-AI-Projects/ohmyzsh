# UFW plugin

This plugin adds completion for managing the Uncomplicated Firewall (UFW),
a simple interface for managing iptables. Learn more about [`UFW`](https://wiki.ubuntu.com/UncomplicatedFirewall).

To use it, add ufw to the plugins array of your zshrc file:
```
plugins=(... ufw)
```

Some of the commands include:

* `allow PORT[/PROTOCOL]` add an allow rule
* `default` set default policy
* `delete PORT[/PROTOCOL]` delete RULE
* `deny PORT[/PROTOCOL]` add deny rule
* `disable` disables the firewall
* `enable` enables the firewall
* `route` add route rule
