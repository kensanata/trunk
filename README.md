# Trunk for Mastodon

Trunk allows you to mass-follow a bunch of people in order to get
started with [Mastodon](https://joinmastodon.org/). Mastodon is a
free, open-source, decentralized microblogging network.

Issues, feature requests and all that: use the
[Software Wiki](https://alexschroeder.ch/software/Trunk).

## Logo

Logo kindly donated by [Jens Reuterberg](https://www.ohyran.se/).

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
- `MCE`

You should now be able to run the web application. From the working
directory, start the development server:

```
morbo trunk.pl
```

This allows you to make changes to `trunk.pl` and check the result on
`localhost:3000` after every save.

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

- we also pass requests to `https://communitywiki.org/mojo` on to port
  8080 because that gives us the rainbow dinosaur when the server runs
  into errors

```
<VirtualHost *:80>
    ServerName communitywiki.org
    ServerAlias www.communitywiki.org
    Redirect permanent / https://communitywiki.org/
</VirtualHost>
<VirtualHost *:443>
    ServerName www.communitywiki.org
    Redirect permanent / https://communitywiki.org/
    SSLEngine on
    SSLCertificateFile      /var/lib/dehydrated/certs/communitywiki.org/cert.pem
    SSLCertificateKeyFile   /var/lib/dehydrated/certs/communitywiki.org/privkey.pem
    SSLCertificateChainFile /var/lib/dehydrated/certs/communitywiki.org/chain.pem
    SSLVerifyClient None
</VirtualHost>
<VirtualHost *:443>
    ServerAdmin alex@communitywiki.org
    ServerName communitywiki.org
    DocumentRoot /home/alex/communitywiki.org

    RewriteEngine on
    RewriteCond "%{HTTP_USER_AGENT}" "Mastodon" [OR]
    RewriteCond "%{HTTP_USER_AGENT}" "Pcore"
    RewriteRule ".*" "-" [redirect=403,last]

    SSLEngine on
    SSLCertificateFile      /var/lib/dehydrated/certs/communitywiki.org/cert.pem
    SSLCertificateKeyFile   /var/lib/dehydrated/certs/communitywiki.org/privkey.pem
    SSLCertificateChainFile /var/lib/dehydrated/certs/communitywiki.org/chain.pem
    SSLVerifyClient None

    ProxyPass /mojo             http://communitywiki.org:8080/mojo
    ProxyPass /trunk            http://communitywiki.org:8080/trunk

</VirtualHost>
```

## Configuration

You need a config file in the same directory, called `trunk.conf`.
This is where you define your admins, if any.

No admins:

```perl
{}
```

One admin:

```perl
{
  users => { alex => 'fantastic password!' },
}
```

## Deployment

I'd say, run it using `morbo` and click around. If it appears to work,
either start is as a daemon, or use `hypnotoad` (which is part of
Mojolicious). If you already have other Mojolicious applications, use
[Toadfarm](https://metacpan.org/pod/Toadfarm). If you want the
features of your regular webserver as well, use it as a proxy.

On my system, for example, I use `Toadfarm` to start it. It listens on
port 8080. My site is served by Apache:

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
	# you definitely need to look at this part
    <Directory /home/alex/communitywiki.org>
        # need CGI Script execution for legacy apps
        Options ExecCGI Includes Indexes MultiViews SymLinksIfOwnerMatch
        AddHandler cgi-script .pl
        AllowOverride All
		Require all granted
    </Directory>

    # block Mastodon from fetching preview images and bringing my server down
    RewriteEngine on
    RewriteCond "%{HTTP_USER_AGENT}" "Mastodon"
    RewriteRule ".*" "-" [redirect=403,last]

	# same as above; this uses dehydrated to manage certificates by Let's Encrypt
    SSLEngine on
    SSLCertificateFile      /var/lib/dehydrated/certs/communitywiki.org/cert.pem
    SSLCertificateKeyFile   /var/lib/dehydrated/certs/communitywiki.org/privkey.pem
    SSLCertificateChainFile /var/lib/dehydrated/certs/communitywiki.org/chain.pem
    SSLVerifyClient None

	# these are the various applications running here, we only care about the last one
    ProxyPass /wiki             http://communitywiki.org:8080/wiki
    ProxyPass /mark             http://communitywiki.org:8080/mark
    ProxyPass /mojo             http://communitywiki.org:8080/mojo
    ProxyPass /food             http://communitywiki.org:8080/food
    ProxyPass /trunk            http://communitywiki.org:8080/trunk

</VirtualHost>
```

## Bugs

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
