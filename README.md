# rubyfarmer

![https://raw.github.com/wiki/yukisov/web-sindan-crawler/](rubyfarmer.png?raw=true)

This is a tool for updating [rubylang/rubyfarm](https://hub.docker.com/r/rubylang/rubyfarm/tags/).

* fetches [the ruby repository](https://github.com/ruby/ruby.git),
* build each not-built-yet commit,
* creates a docker image, and
* pushes docker hub: [rubylang/rubyfarm](https://hub.docker.com/r/rubylang/rubyfarm/tags/).

## How to use rubylang/rubyfarm

```
$ docker pull rubylang/rubyfarm:latest
$ docker run --rm -ti rubylang/rubyfarm:latest
# ruby -v
ruby 2.7.0dev (2019-02-13 trunk 67066) [x86_64-linux]
```

## How to setup rubyfarmer

1. `docker login`
2. Test it manually: `ruby rubyfarmer.rb`
3. Set it as a cron job:

```
0 * * * * SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/XXX/XXX /path/to/rubyfarmer.rb
```
