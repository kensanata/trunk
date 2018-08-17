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
either start is as a daemon, or use `Hypnotoad`. If you already have
other Mojolicious applications, use `Toadfarm`.

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
