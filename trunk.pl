#!/usr/bin/env perl
use Mojolicious::Lite;
use Text::Markdown 'markdown';
use File::Basename;
use File::Slurp;
use Mastodon::Client;
use Encode qw(decode_utf8);

my $dir = "/home/alex/src/trunk";            # FIXME
my $uri = "https://communitywiki.org/trunk"; # FIXME

sub to_markdown {
  my $file = shift;
  my $md = read_file("$dir/$file") || die "Cannot open $dir/$file: $!";
  return markdown(decode_utf8($md));
}

get '/' => sub {
  my $c = shift;
  # if we're here because of the redirect uri
  my $code = $c->param('code');
  if ($code) {
    my $action = $c->cookie('action');
    my $account = $c->cookie('account');
    my $name = $c->cookie('name');
    if ($action) {
      my $url = $c->url_for("do_$action")->query(code => $code, account => $account, name => $name);
      $c->redirect_to($url);
    } else {
      $c->render(template => 'error',
		 msg => "We got back an authorization code "
		 . "but the cookie was lostand now we don't know what to do!");
    }
    return;
  }
  my $md = to_markdown('index.md');
  my @lists;
  my @empty_lists;
  for my $file (sort { lc($a) cmp lc($b) } <$dir/*.txt>) {
    my ($name, $path, $suffix) = fileparse($file, '.txt');
    my $size = -s $file;
    if ($size) {
      push(@lists, $name);
    } else {
      push(@empty_lists, $name);
    }
  }
  $c->render(template => 'index', md => $md,
	     lists => \@lists, empty_lists => \@empty_lists);
} => 'main';

get '/grab/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  my @accounts = sort { lc($a) cmp lc($b) } split(" ", read_file("$dir/$name.txt"));
  $c->render(template => 'grab', name => $name, accounts => \@accounts);
} => 'grab';

get '/follow/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  # this will send us to /auth
  $c->render(template => 'login', name => $name, action => 'follow');
} => 'follow';

post '/auth' => sub {
  my $c = shift;
  my $account = $c->param('account');
  my $action = $c->param('action');
  my $name = $c->param('name');
  $c->cookie(account => $account, {expires => time + 60});
  $c->cookie(action => $action, {expires => time + 60});
  $c->cookie(name => $name, {expires => time + 60});
  my $client = client($c, $account);
  if ($client) {
    $c->redirect_to($client->authorization_url());
  } else {
    $c->render(template => 'error', msg => "Login failed!");
  }
} => 'auth';

sub client {
  my $c = shift;
  my $account = shift;
  my ($who, $where) = split(/@/, $account);
  if (not $where) {
    $c->render(template => 'error',
	       msg => "Account must look like an email address, "
	       . 'e.g. kensanata@octodon.social');
    return;
  }
  my ($instance, $client_id, $client_secret);
  my $file = "$dir/credentials";
  if (open(my $fh, "<", $file)) {
    while (my $line = <$fh>) {
      next unless $line;
      ($instance, $client_id, $client_secret) = split(" ", $line);
      last if $instance eq $where;
    }
  }
  my %attributes = (
    instance	    => $where,
    redirect_uri    => $uri,
    scopes          => ['follow', 'read', 'write'],
    name	    => 'Trunk',
    website	    => $uri,
 );
  my $client;
  if ($instance and $instance eq $where) {
    $attributes{client_id}     = $client_id;
    $attributes{client_secret} = $client_secret;
    $client = Mastodon::Client->new(%attributes);
  } else {
    $client = Mastodon::Client->new(%attributes);
    $client->register();
    open(my $fh, ">>", $file) || die "Cannot write $file: $!";
    my $instance = $client->instance->uri;
    $instance =~ s!^https://!!;
    print $fh join(" ", $instance,
		   $client->client_id,
		   $client->client_secret) . "\n";
    close($fh) || die "Cannot close $file: $!";
  }
  return $client;
}

get 'do/follow' => sub {
  my $c = shift;

  my $code = $c->param('code'); # this is the authorization code!
  if (!$code) {
    $c->render(template => 'error',
	       msg => "We failed to get an authorization code.");
    return;
  }

  my $account = $c->param('account');
  if (!$account) {
    $c->render(template => 'error',
	       msg => "We did not find the account in the cookie.");
    return;
  }

  my $name = $c->param('name');
  if (!$name) {
    $c->render(template => 'error',
	       msg => "We did not find the list name in the cookie.");
    return;
  }

  my $client = client($c, $account);

  if (!$client) {
    $c->render(template => 'error',
	       msg => "Something about this login went wrong.");
    return;
  }

  warn("Authorize");
  eval {
    $client->authorize(access_code => $code);
  };
  if ($@) {
    $c->render(template => 'error',
	       msg => "Authorisation failed!");
    return;
  }

  # get the new accounts we're supposed to follow (strings)
  my @accts = split(" ", read_file("$dir/$name.txt"));

  my @ids;
  for my $acct(@accts) {
    # and follow it
    warn("Remote follow $acct");
    eval {
      my $account = $client->remote_follow($acct);
      # and remember to add it to the list
      push(@ids, $account->{id});
    };
    # ignore errors: if we're already subscribed then that's fine
  }

  warn("Create $name");
  # create the list
  my $list = $client->post('lists', {title => $name});

  warn("Add @ids");
  # and add the new accounts we're following to the new list
  my $id = $list->{id};
  $client->post("lists/$id/accounts" => {account_ids => \@ids});

  # done!
  $c->render(template => 'follow', name => $name, accts => \@accts);
} => 'do_follow';

app->defaults(layout => 'default');
app->start;

__DATA__


@@ login.html.ep
% title 'Mastodon';
<h1>Login</h1>

<p>Please provide your account. You will be redirected to a login page. Once you
are logged in, we will proceed to <%= $action %>
<%= link_to grab => {name => $name} => begin%><%= $name %><%= end %>.</p>

<p>
%= form_for auth => (method => 'POST') => begin
%= text_field 'account'
%= hidden_field name => $name
%= hidden_field action => $action
%= submit_button
% end


@@ follow.html.ep
% title 'Follow a List';
<h1><%= $name %></h1>

<p>We created the <em><%= $name %></em> list for you. Note that if you visit
this list in the Mastodon web client, it will will appear empty. In fact, this
is what it will say:</p>

<blockquote>"There is nothing in this list yet. When members of this list post
new statuses, they will appear here."</blockquote>

<p>Click on the button with the three sliders ("Show settings") and then on
"Edit lists" and only then will you see the people in the list!</p>

<P>Enjoy! 👍</p>

<ul>
% for my $account (@$accts) {
<li>
% my ($username, $instance) = split(/@/, $account);
<a href="https://<%= $instance %>/@<%= $username %>">
%= $account
</a>
</li>
% }
</ul>

@@ grab.html.ep
% title 'Grab a List';
<h1><%= $name %></h1>

<p>Below are some people for you to follow. If you click the button below in
order to follow them all, what will happen is that we will create a list called
<em><%= $name %></em> for your account and we'll put any of these that you're
not already following into this list. If you already have a list with the same
name, don't worry: you can have lists sharing the same name.</p>

%= button_to "Follow $name" => follow => {name => $name } => (class => 'button')

<p>Here's the list of accounts for the <em><%= $name %></em> list. You can of
course pick and choose instead of following them all, using Mastodon's
<em>remote follow</em> feature.</p>

<ul>
% for my $account (@$accounts) {
<li>
% my ($username, $instance) = split(/@/, $account);
<a href="https://<%= $instance %>/users/<%= $username %>/remote_follow" class="button">Follow</a>
<a href="https://<%= $instance %>/@<%= $username %>">
%= $account
</a>
</li>
% }
</ul>

@@ index.html.ep
% title 'Trunk for Mastodon';
<%== $md %>

<ul>
% for my $name (@$lists) {
<li>
%= link_to grab => {name => $name} => begin
%= $name
% end
</li>
% }
</ul>

Empty lists:

<ul>
% for my $name (@$empty_lists) {
<li>
%= link_to grab => {name => $name} => begin
%= $name
% end
</li>
% }
</ul>


@@ error.html.ep
% title 'Error';
<h1>Error</h1>
<p>
%= $msg
</p>


@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
<head>
<title><%= title %></title>
%= stylesheet begin
body {
  padding: 1em;
  max-width: 72ex;
  font-size: 18pt;
  font-family: "DejaVu Serif", serif;
}
.button {
  display: inline;
}
form.button input, a.button {
  font-family: "DejaVu Sans", sans;
  font-size: 14pt;
  background: #2b90d9;
  color: #fff;
  padding: 10px;
  margin-bottom: 10px;
  margin-right: 10px;
  border-radius: 4px;
  text-transform: uppercase;
  text-decoration: none;
  text-align: center;
  cursor: pointer;
  font-weight: 500;
  border: 0;
}
li { display: block; margin-bottom: 20pt; }
.logo {float: right; }
% end
<meta name="viewport" content="width=device-width">
</head>
<body>
<img class="logo" src="trunk-logo.jpg" />
<%= content %>
<hr>
<p>
<a href="https://communitywiki.org/trunk">Trunk</a>&#x2003;
<a href="https://alexschroeder.ch/cgit/trunk/about/">Source</a>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
