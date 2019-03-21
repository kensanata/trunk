# Trunk for Mastodon

Trunk allows you to mass-follow a bunch of people in order to get
started with [Mastodon](https://joinmastodon.org/). Mastodon is a
free, open-source, decentralized microblogging network.

Issues, feature requests and all that: use the
[Software Wiki](https://alexschroeder.ch/software/Trunk).

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Logo](#logo)
- [API](#api)
    - [Getting the lists](#getting-the-lists)
    - [Getting the accounts in a list](#getting-the-accounts-in-a-list)
    - [Get the queue](#get-the-queue)
    - [Add to the queue](#add-to-the-queue)
    - [Remove from the queue](#remove-from-the-queue)
- [Installation](#installation)
    - [Configuration](#configuration)
    - [Deployment](#deployment)
    - [Bugs](#bugs)
- [Troubleshooting](#troubleshooting)
- [Translation](#translation)
- [Queue Bot](#queue-bot)
    - [First, create a bot account and set everything up](#first-create-a-bot-account-and-set-everything-up)
    - [Finally, invoke it](#finally-invoke-it)
- [Test](#test)

<!-- markdown-toc end -->


## Logo

Logo kindly donated by [Jens Reuterberg](https://www.ohyran.se/).

## API

There's a simple API right now.

### Getting the lists

```
GET /trunk/api/v1/list
```

This returns a list of strings. Each of these strings is a list name.

Example:

```
curl https://communitywiki.org/trunk/api/v1/list
```

### Getting the accounts in a list

```
GET /trunk/api/v1/list/:name
```

This returns a list of objects. Each of these objects has the following attribute:

* `acct` is the simple account, e.g. `kensanata@octodon.social`

Needless to say, the list name has to be encoded appropriately.

Example:

```
curl https://communitywiki.org/trunk/api/v1/list/Information%20Technology
```

### Get the queue

```
GET /trunk/api/v1/queue
```

You will get back a list of objects with the following attributes:

* `acct` is the simple account, e.g. `kensanata@octodon.social`
* `names` is a list of existing list names

The oldest items in the queue come first.

### Add to the queue

```
POST /trunk/api/v1/queue
```

You need to pass the following parameters:

* `username` is your username as provided for admins
* `password` is your password as provided for admins
* `acct` is the simple account, e.g. `kensanata@octodon.social`
* `name` is the name an existing list (may occur multiple times)

### Remove from the queue

```
DELETE /trunk/api/v1/queue
```

You need to pass along an object with the following attribute:

* `username` is your username as provided for admins
* `password` is your password as provided for admins
* `acct` is the simple account, e.g. `kensanata@octodon.social`

## Installation

If you want to install it, you need a reasonable Perl installation. If
this is your only Perl application you're developing, I'm not going to
bother telling you about [Perlbrew](https://perlbrew.pl/), which
allows you to install multiple versions of Perl. I'm just going to
assume you have a system with Perl installed.

The first thing I suggest you do is install a better tool to install
your dependencies: `cpanm` from the `App::cpanminus` package.

- [Installing App::cpanminus](https://metacpan.org/pod/App::cpanminus#INSTALLATION)

Then use `cpanm` to install the following:

- `Mojolicious`
- `Mojolicious::Plugin::Config`
- `Mojolicious::Plugin::Authentication`
- `Mastodon::Client`
- `Text::Markdown`
- `List::Util`
- `MCE`

If these modules get installed into `~/perl5` then you need to make
sure `~/perl5/bin` is in your `PATH` and that `/perl5/lib/perl5` is in
your `PERL5LIB`. At the end of my `~/.bashrc`, for example:

```bash
PATH="/home/alex/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="/home/alex/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
```

You should now be able to run the web application. From the working
directory, start the development server:

```
morbo trunk.pl
```

This allows you to make changes to `trunk.pl` and check the result on
`localhost:3000` after every save.

### Configuration

The keys to set:

* `users` a hash of usernames and passwords defining your admins
  (defaults to none)
* `dir` sets the data directory (defaults to the current directory)
* `uri` sets the redirection URI (defaults to
  `https://communitywiki.org/trunk`)
* `bot` sets the account for the bot, if you have one (defaults to
  `trunk@botsin.space`)
* `pass` sets the
  [passphrase](https://mojolicious.org/perldoc/Mojolicious/Guides/FAQ#What-does-Your-secret-passphrase-needs-to-be-changed-mean)
  in case you're wondering about the "Your secret passphrase needs to
  be changed" message in your logs.

Example setup:

```
{
  users => {
    alex => 'Holz',
  },
  uri => 'http://localhost:3000',
  dir => '/home/alex/src/trunk',
  bot => 'trunk@botsin.space',
}
```

### Deployment


Once you are ready to deploy there are various options. The simplest
option is to just start it as a daemon, but listening to a different
port:

```
perl trunk.pl daemon --listen "http://*:8080"
```

The next option you have is to use a tool called `hypnotoad` which
should have come with one of the dependencies you installed. This
defaults to port 8080, so you're good:

```
hypnotoad trunk.pl
```

If you change the file, you can restart it gracefully with zero
downtime by simply running the same command again.

Hypnotoad writes a PID into the `hypnotoad.pid` file so in order to
kill the server, use the following:

```
kill $(cat hypnotoad.pid)
```

Ideally, you would be running the application on your server using
Hypnotoad and use Apache in front of it. Here's an example site
configuration from my `/etc/apache2/sites-enabled` directory.
Here's what it does:

- it redirects HTTP requests from port 80 to port 443 for both
  `communitywiki.org` and `www.communitywiki.org`

- it redirects `www.communitywiki.org` to `communitywiki.org`,
  specifying the certificates I got from [Let's
  Encrypt](https://letsencrypt.org/) which I manage using
  [dehydrated](https://github.com/lukas2511/dehydrated#dehydrated-)
  (you need to find your own favorite way of securing your site)

- it serves static files from `/home/alex/communitywiki.org`, the
  document root, for `communitywiki.org` using SSL, as described above
  (you might want to change the directory, of course)

- if a client identifies as Mastodon or Pcore, we tell them that
  they're forbidden (403), because these clients have brought this
  particular site down in the past (this is entirely optional)

- and finally, requests to `https://communitywiki.org/trunk` get
  passed on to port 8080, which is where our server is waiting

```apache
<VirtualHost *:80>
    # all HTTP gets redirected to HTTPS
    ServerName communitywiki.org
    ServerAlias www.communitywiki.org
    Redirect permanent / https://communitywiki.org/
</VirtualHost>
<VirtualHost *:443>
    # all traffic to www gets redirected to the same site without www
    ServerName www.communitywiki.org
    Redirect permanent / https://communitywiki.org/
    SSLEngine on
    SSLCertificateFile      /var/lib/dehydrated/certs/communitywiki.org/cert.pem
    SSLCertificateKeyFile   /var/lib/dehydrated/certs/communitywiki.org/privkey.pem
    SSLCertificateChainFile /var/lib/dehydrated/certs/communitywiki.org/chain.pem
    SSLVerifyClient None
</VirtualHost>
<VirtualHost *:443>
    # this is the real server
    ServerAdmin alex@communitywiki.org
    ServerName communitywiki.org
    DocumentRoot /home/alex/communitywiki.org

    # block Mastodon and others from fetching preview images and bringing my server down
    RewriteEngine on
    RewriteCond "%{HTTP_USER_AGENT}" "Mastodon" [OR]
    RewriteCond "%{HTTP_USER_AGENT}" "Pcore"
    RewriteRule ".*" "-" [redirect=403,last]

	# same as above; this uses dehydrated to manage certificates by Let's Encrypt
    SSLEngine on
    SSLCertificateFile      /var/lib/dehydrated/certs/communitywiki.org/cert.pem
    SSLCertificateKeyFile   /var/lib/dehydrated/certs/communitywiki.org/privkey.pem
    SSLCertificateChainFile /var/lib/dehydrated/certs/communitywiki.org/chain.pem
    SSLVerifyClient None

	# this is the web application we care about
    ProxyPass /trunk            http://communitywiki.org:8080

</VirtualHost>
```

Actually, if you want to run multiple applications, they each need to
listen on a different port, or you make them listen for a different
mount point.

Assume you change the Apache config file above to end with the following:

```apache
    # with a mount point
    ProxyPass /trunk            http://communitywiki.org:8080/trunk
```

Then create a new Mojolicious application which does nothing else but
use the `Mount` plugin to mount `trunk.pl` under `/trunk`:

```perl
use Mojolicious::Lite;
plugin Mount => {'/trunk' => './trunk.pl'};
app->start;
```

Now start this file instead of `trunk.pl` using `hypnotoad` and it
should still work.

### Bugs

Version 0.015 of `Mastodon::Client` has a bug which you need to fix:

```diff
diff -u /home/alex/perl5/lib/perl5/Mastodon/Client.pm\~ /home/alex/perl5/lib/perl5/Mastodon/Client.pm
--- /home/alex/perl5/lib/perl5/Mastodon/Client.pm~	2018-08-11 22:22:04.294122849 +0200
+++ /home/alex/perl5/lib/perl5/Mastodon/Client.pm	2018-08-12 10:26:27.282692089 +0200
@@ -452,10 +452,10 @@
 }
 
 # POST requests with no data and a mandatory ID number
-foreach my $pair ([
+foreach my $pair (
     [ statuses => [qw( reblog unreblog favourite unfavourite     )] ],
     [ accounts => [qw( mute unmute block unblock follow unfollow )] ],
-  ]) {
+  ) {
 
   my ($base, $endpoints) = @{$pair};
 

Diff finished.  Wed Aug 15 09:48:54 2018
```

## Troubleshooting

If you're seeing the barfing Tyrannosaurus Rex or the "raptor not
found" message, that means that Trunk has run into an error. Your best
option is to run the server using `morbo` and repeat whatever you did.
When running with `morbo`, you should get better error output in your
browser and a backtrace in the `morbo` output.

## Translation

If you want to translate the application, there are two things you
need to do.

First, you want to translate the Markdown files. These are the files
that can be edited via the admin interface via *Describe a list* →
*Special descriptions*.

* `help.md` is the help page
* `index.md` is shown on the front page
* `request.md` is the request to join linked from the front page
* `grab.md` is the intro for the grab page, where the list members are listed

Second, you want to translate all the templates that are included at
the end of `trunk.pl` in the `__DATA__` section. In order to do that,
run the following command:

```sh
perl trunk.pl inflate
```

This generates external copies of all the template files. Check the
new `templates` folder. All the files ending in `.html.ep` can be
translated and take precedence over the templates stored inside
`trunk.pl`. This is how you can translate the templates and still
install a new copy of `trunk.pl`.

## Queue Bot

The Trunk interface has a queue which can be fed using the API. One
way of doing that involves a bot. This bot is written in Python.
Assuming you have a Python 3 installation, here's how to install the
prerequisites:

```
pip3 install Mastodon.py
pip3 install html2text
pip3 install requests
```

### First, create a bot account and set everything up

Mastodon provides a UI for all of this. Just go to your settings and
under the "developer" menu there is a place to create a new app and
get your credentials all in one go. We've set up *trunk@botsin.space*
for us.

Got to Settings → Development and create a new application.

1. give it the name of your Trunk instance
2. use the URL for your Trunk instance
3. don't change the default URI
4. we need read:notifications, read:statuses, write:notifications, and
   write:statuses
5. submit
6. click on the link to your application

You need to save the three codes you got as follows:

The *Client Key* and *Client Secret* go into the first file, each on a
line of its own. The filename is `<account>.client`, for example
`trunk@botsin.space.client`.

Example content:

```
1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
```

The *Access Token* goes to a separate file called `<account>.user`,
for example `trunk@botsin.space.user`.

Example content:

```
7890abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456
```

### Finally, invoke it

You need to invoke the bot with the user account it should check and
the URL for the Trunk instance to use, and the admin username and
password on that trunk instance.

This is what I do:

```
./bots.py trunk@botsin.space https://communitywiki.org/trunk trunk '*secret*'
```

Do this from a cronjob once an hour or so, and it should work:

1. it checks for new notifications
2. if they look like Trunk requests, they're added to the queue

## Test

The unit tests are simple. The following runs all the tests in the `t`
directory.

```
prove t
```

Create the bot on an instance and save the credentials in the
`*.client` and `*.user` files as instructed above.

Create a list:

```
touch Test.txt
```

Start the server locally:

```
morbo trunk.pl
```

Use your favorite account (I'm going to use
*kensanata@octodon.social*) and send a message to the bot (I'm going
to use *trunk@botsin.space*):

> @trunk Please add me to Test.

If you're logged in with your bot account, you should get a
notification.

Run the bot, using your bot account and a username and password from
your trunk.conf:

```
python3 bot.py trunk@botsin.space http://localhost:3000 alex Holz
```

Check that the bot dismissed the notification by reloading the web UI
of your bot account.

Check that the bot added your request to the queue by visiting
`http://localhost:3000/queue`

In the queue, click the OK button.

You should see the following:

> The account kensanata@octodon.social was added to the following
> lists: Test

You should also see that the bot replied to your original request:

> @kensanata Done! Added you to Test. 🐘
