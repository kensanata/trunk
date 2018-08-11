#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::Cache;
use Text::Markdown 'markdown';
use File::Basename;
use File::Slurp;
use Mastodon::Client;
use Encode qw(decode_utf8);
my $dir = "/home/alex/src/trunk"; # FIXME
my $cache = Mojo::Cache->new(max_keys => 50);

sub to_markdown {
  my $file = shift;
  my $md = read_file("$dir/$file") || die "Cannot open $dir/$file: $!";
  return markdown($md);
}

get '/' => sub {
  my $c = shift;
  my $md = to_markdown('index.md');
  my @names = sort map {
    my ($name, $path, $suffix) = fileparse($_, '.txt');
    $name;
  } <$dir/*.txt>;
  $c->render(template => 'index', md => $md, names => \@names);
} => 'main';

get '/grab/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  my @accounts = sort split(" ", read_file("$dir/$name.txt"));
  $c->render(template => 'grab', name => $name, accounts => \@accounts);
} => 'grab';

get '/follow/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  $c->render(template => 'login', name => $name, action => 'follow');
} => 'follow';

post '/auth' => sub {
  my $c = shift;
  my $account = $c->param('account');
  my $action = $c->param('action');
  my $name = $c->param('name');
  my $uri = $c->url_for("do_$action", name => $name);
  my $result = oauth($c, $account, $uri);
  $c->redirect_to($result) if $result;
} => 'auth';

sub oauth {
  my $c = shift;
  my $account = shift;
  my $uri = shift;
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
      ($instance, $client_id, $client_secret) = split(" ", $line);
      last if $instance eq $where;
    }
  }
  my %attributes = (
    instance	    => $where,
    scopes          => ['read', 'write', 'follow'],
    name	    => 'Trunk',
    website	    => 'https://communitywiki.org/trunk',
    redirect_uri    => "$uri",
    coerce_entities => 1,
  );
  my $client;
  if ($instance and $instance eq $where) {
    $attributes{client_id}	= $client_id;
    $attributes{client_secret} = $client_secret;
    $client = Mastodon::Client->new(%attributes);
  } else {
    $client = Mastodon::Client->new(%attributes);
    $client->register();
    open(my $fh, ">>", $file) || die "Cannot write $file: $!";
    print $fh join(" ", $instance, $client_id, $client_secret) . "\n";
    close($fh) || die "Cannot close $file: $!";
  }
}

post 'do/follow/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  $c->render(text => template => 'login', name => $name, action => 'follow');
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


@@ grab.html.ep
% title 'Grab a List';
<h1><%= $name %></h1>

<p>Below are some people for you to follow. If you click the button below in
order to follow them all, what will happen is that we will create a list called
<em><%= $name %></em> for your account and we'll put any of these that you're
not already following into this list.</p>

%= button_to "Follow $name" => follow => {name => $name } => (class => 'button')

<p>If you've made a mistake, you can still undo it. If you click the button
below to unfollow them all, we will unfollow all the people on your <em><%=
$name %></em> list, and we'll delete your list if it is empty. Thus, if you
followed some of these people before, they didn't get put on your <em><%= $name
%></em> list when you clicked the button above, and so you'll still be following
them if you click the button bellow. No problem. If you added extra people to
your <em><%= $name %></em> list, then these people are not on the list below and
therefore they will not get removed from your <em><%= $name %></em> list. Again,
no problem. The only problem we can't fix is if you followed some of these
people before and then added them to your <em><%= $name %></em> list. Since they
are in your <em><%= $name %></em> list, and they are on the list below, clicking
the button will unfollow these people. I still think it's the best we can do,
however.<p>

%= button_to "Unfollow $name" => unfollow => {name => $name } => (class => 'button')

<p>And finally, the list of accounts. You can of course pick and
choose as well, using Mastodon's <em>remote follow</em> feature.</p>

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
% for my $name (@$names) {
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
  max-width: 72em;
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
li { display: block; }
% end
<meta name="viewport" content="width=device-width">
</head>
<body>
<%= content %>
<hr>
<p>
<a href="https://communitywiki.org/trunk">Trunk</a>&#x2003;
<a href="https://alexschroeder.ch/cgit/trunk/about/">Source</a>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
