#!/usr/bin/env perl
use Mojolicious::Lite;
use Mastodon::Client;
use Mojo::File;
use Mojo::Log;
use Text::Markdown 'markdown';
use Encode qw(decode_utf8);

my $dir = "/home/alex/src/trunk";            # FIXME
my $uri = "https://communitywiki.org/trunk"; # FIXME

my $log = Mojo::Log->new(path => "$dir/admin.log", level => 'info');

plugin 'RenderFile';
plugin 'Config' => {default => {users => {}}};

plugin 'authentication', {
    autoload_user => 1,
    load_user => sub {
        my ($self, $username) = @_;
        return {
	  'username' => $username,
	} if app->config('users')->{$username};
        return undef;
    },
    validate_user => sub {
        my ($self, $username, $password) = @_;
	if (app->config('users')->{$username}
	    && $password eq app->config('users')->{$username}) {
	  return $username;
	}
        return undef;
    },
};

sub to_markdown {
  my $file = shift;
  my $path = Mojo::File->new("$dir/$file");
  my $md = $path->slurp || die "Cannot open $dir/$file: $!";
  return markdown(decode_utf8($md));
}

get '/' => sub {
  my $c = shift;
  # if we're testing locally
  if ($c->url_for->to_abs =~ /localhost:3000/) {
    $uri = 'http://localhost:3000/';
  }
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
		 . "but the cookie was lost. This looks like a bug.");
    }
    return;
  }
  my $md = to_markdown('index.md');
  my @lists;
  my @empty_lists;
  for my $file (sort { lc($a) cmp lc($b) } <$dir/*.txt>) {
    my $size = -s $file;
    my $name = Mojo::File->new($file)->basename('.txt');
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
  my $path = Mojo::File->new("$dir/$name.txt");
  my @accounts = sort { lc($a) cmp lc($b) } split(" ", $path->slurp);
  $c->render(template => 'grab', name => $name, accounts => \@accounts);
} => 'grab';

get '/follow/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  # this will send us to /auth
  $c->render(template => 'auth', name => $name, action => 'follow');
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

  eval {
    $client->authorize(access_code => $code);
  };
  if ($@) {
    $c->render(template => 'error',
	       msg => "Authorisation failed!");
    return;
  }

  # get the new accounts we're supposed to follow (strings)
  my $path = Mojo::File->new("$dir/$name.txt");
  my @accts = split(" ", $path->slurp);

  my @ids;
  for my $acct(@accts) {
    # and follow it
    eval {
      my $account = $client->remote_follow($acct);
      # and remember to add it to the list
      push(@ids, $account->{id});
    };
    # ignore errors: if we're already subscribed then that's fine
  }

  # create the list
  my $list = $client->post('lists', {title => $name});

  # and add the new accounts we're following to the new list
  my $id = $list->{id};
  $client->post("lists/$id/accounts" => {account_ids => \@ids});

  # done!
  $c->render(template => 'follow', name => $name, accts => \@accts);
} => 'do_follow';


get '/logo' => sub {
  my $c = shift;
  $c->render_file('filepath' => "$dir/trunk-logo.jpg");
};


get '/admin' => sub {
  my $c = shift;
  $c->render();
};
  

get '/add' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'add'));
  }
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <$dir/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(template => 'add', lists => \@lists);
};

get '/login' => sub {
  my $c = shift;
  my $action = $c->param('action');
  my $username = $c->param('username');
  my $password = $c->param('password');
  if ($username) {
    $c->authenticate($username, $password);
    if ($c->is_user_authenticated()) {
      return $c->redirect_to($action);
    } else {
      $c->stash(login => 'wrong');
    }
  }
  $c->render(template => 'login', action => $action);
};

sub backup {
  my $path = shift;
  if (! -e "$path~") {
    $path->copy_to("$path~");
  } else {
    my $i = 1;
    while (-e "$path.~$i~") {
      $i++;
    }
    $path->copy_to("$path.~$i~");
  }
}

sub add_account {
  my $path = shift;
  my $account = shift;
  my %accounts = map { $_ => 1 } split(" ", $path->slurp);
  if (not $accounts{$account}) {
    backup($path);
    my $fh = $path->open(">>:encoding(UTF-8)") || die "Cannot write to $path: $!";
    print $fh "$account\n";
    close($fh);
  }
}

post '/do/add' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'add'));
  }
  my $user = $c->current_user->{username};
  my $account = $c->param('account');
  $account =~ s/^@//;   # trim extra @ at the beginning
  $account =~ s/^\s+//; # trim leading whitespace
  $account =~ s/\s+$//; # trim trailing whitespace
  my $hash = $c->req->body_params->to_hash;
  delete $hash->{account};
  my @lists = sort { lc($a) cmp lc($b) } keys %$hash;
  local $" = ", ";
  $log->info("$user added $account to @lists");
  for my $name (@lists) {
    add_account(Mojo::File->new("$dir/$name.txt"), $account);
  }
  $c->render(template => 'do_add', account => $account, lists => \@lists);
} => 'do_add';

app->defaults(layout => 'default');
app->start;

__DATA__


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


@@ auth.html.ep
% title 'Login to Mastodon Instance';
<h1>Which account to use?</h1>

<p>Please provide the account you want to use. Don not provide your email
address: I'd use kensanata@octodon.social instead of kensanata@gmail.com, for
example. You will be redirected to your instance. There, you need to authorize
the Trunk application to act on your behalf. If you do, Trunk will proceed to
<%= $action %> <%= link_to grab => {name => $name} => begin%><%= $name %><%= end
%>. If you prefer not to do that, no problem. Just go back to the list and go
through the list manually.</p>

%= form_for auth => (method => 'POST') => begin
%= text_field 'account'
%= hidden_field name => $name
%= hidden_field action => $action
%= submit_button
% end


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

<ul class="follow">
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


@@ admin.html.ep
% title 'Trunk Admins';
<h1>Administration</h1>

<p>Hello and thank you for helping administrate the Trunk lists! The following
tasks all require you to be logged in. Please note that admin actions will be
logged, just in case.</p>

<ul>
<li>
%= link_to 'Add a user' => 'add'
</li>
</ul>


@@ add.html.ep
% title 'Add an account';
<h1>Add an account</h1>

%= form_for do_add => begin
%= label_for account => 'Account'
%= text_field 'account'

<p>Lists:
% join("<br /\n", map {
%= check_box $_
%= $_
% } (@$lists));
</p>

%= submit_button
% end


@@ do_add.html.ep
% title 'Add an account';
<h1>Add a user</h1>

<p>The user <%= $account %> was added to the following lists:
%= join(", ", @$lists);
</p>

<p>
%= link_to 'Add another user' => 'add'
</p>

@@ login.html.ep
% layout 'default';
% title 'Login';
<h1>Login</h1>
<% if ($c->stash('login') eq 'wrong') { %>
<p>
<span class="alert">Login failed. Username unknown or password wrong.</span>
</p>
<% } %>

<p>This action (<%= $action =%>) requires you to login.</p>

%= form_for login => (class => 'login') => begin
%= hidden_field action => $action
%= label_for username => 'Username'
%= text_field 'username'
<p>
%= label_for password => 'Password'
%= password_field 'password'
<p>
%= submit_button 'Login'
% end


@@ logout.html.ep
% layout 'default';
% title 'Logout';
<h1>Logout</h1>
<p>
You have been logged out.
<p>
Go back to the <%= link_to 'main menu' => 'main' %>.


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
.follow li { display: block; margin-bottom: 20pt; }
.logo {float: right; max-height: 300px; }
.alert { font-weight: bold; }
.login label { display: inline-block; width: 12ex; }
% end
<meta name="viewport" content="width=device-width">
</head>
<body>
%= image 'logo', alt => '', class => 'logo'
<%= content %>
<hr>
<p>
<a href="https://communitywiki.org/trunk">Trunk</a>&#x2003;
<a href="https://alexschroeder.ch/cgit/trunk/about/">Source</a>&#x2003;
<%= link_to 'Admins' => 'admin' %>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
