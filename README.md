# Trunk for Mastodon

Trunk allows you to mass-follow a bunch of people in order to get
started with [Mastodon](https://joinmastodon.org/). Mastodon is a
free, open-source, decentralized microblogging network.

Issues, feature requests and all that: use the
[Software Wiki](https://alexschroeder.ch/software/Trunk).

## Logo

Logo kindly donated by [Jens Reuterberg](https://www.ohyran.se/).

## Installation

If you want to install it, you need a reasonable Perl installation. Use `cpanm` to install the following:

- `Mojolicious`
- `Mojolicious::Plugin::Config`
- `Mojolicious::Plugin::Authentication`
- `Mastodon::Client`
- `Text::Markdown`
- `MCE`

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
