#!/usr/bin/env perl
# Trunk is a web application to help find people in the Fediverse
# Copyright (C) 2018-2019  Alex Schroeder <alex@gnu.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use Mojolicious::Lite;
use Mastodon::Client;
use MCE::Loop chunk_size => 1;
use Mojo::Util qw(url_escape);
use Mojo::Log;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Text::Markdown 'markdown';
use Encode qw(decode_utf8 encode_utf8);
use List::Util qw(shuffle);
use utf8;

# Create a file called trunk.conf in the same directory as trunk.pl and override
# these options. For example, use this for testing:
# {users=>{alex=>'Holz'}, uri => 'http://localhost:3000', }
plugin 'Config' => {
  default => {
    users => {},
    pass => "moniker",
    dir => ".",
    uri => "https://communitywiki.org/trunk",
    mass_follow => 1,
    bot => 'trunk@botsin.space',
  }
};

# Change the secret passphrase
app->secrets([app->config('pass')]);

# Use the config to set a global variable...
my $dir = app->config('dir');

plugin Minion => { SQLite => ':temp:' };

# This log is for what the admins do
my $log = Mojo::Log->new(path => "$dir/admin.log", level => 'debug');

# This log is to find bugs...
app->log->level('debug');
app->log->path("$dir/trunk.log");

sub to_markdown {
  my $file = shift;
  my $path = Mojo::File->new("$dir/$file");
  return '' unless -e $path;
  my $md = $path->slurp;
  return markdown(decode_utf8($md));
}

sub error {
  my $c = shift;
  my $msg = shift;
  my $account = $c->cookie('account');
  my $logging = $c->cookie('logging');
  app->log->error("$account: $msg") if $logging;
  $c->render(template => 'error', msg => $msg, status => '500');
  return 0;
}

get '/' => sub {
  my $c = shift;
  # if we're here because of the redirect uri
  my $code = $c->param('code');
  if ($code) {
    my $action = $c->cookie('action');
    my $account = $c->cookie('account');
    my $name = $c->cookie('name');
    my $logging = $c->cookie('logging');
    if ($action) {
      my $url = $c->url_for("do_$action")->query(code => $code, account => $account,
						 name => $name, logging => $logging);
      my $copy = $url;
      $copy =~ s/code=[a-zA-Z0-9]+/code=XXX/;
      app->log->debug("$account is authorized for the '$action' action using the $name list, "
		  . "redirecting to $copy") if $logging;
      return $c->redirect_to($url);
    } else {
      return error($c, "We got back an authorization code "
		   . "but the cookie was lost. This looks like a bug.");
    }
  }
  my $md = to_markdown('index.md');
  my @lists;
  my @empty_lists;
  for my $file (sort { lc($a) cmp lc($b) } <"$dir"/*.txt>) {
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
} => 'index';

get '/grab/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  my $path = Mojo::File->new("$dir/$name.txt");
  my @accounts = shuffle split(" ", $path->slurp);
  my $description = to_markdown("$name.md");
  my $md = to_markdown('grab.md');
  $md =~ s/\$name_encoded/url_escape($name)/ge;
  $md =~ s/\$uri/app->config('uri')/ge;
  $md =~ s/\$name/$name/g;
  $c->render(template => 'grab', name => $name, accounts => \@accounts,
	     description => $description, md => $md,
	     mass_follow => app->config('mass_follow'));
} => 'grab';

get '/follow/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  $c->render(template => 'follow', name => $name);
} => 'follow';

get '/follow_confirm' => sub {
  my $c = shift;
  my $account = $c->param('account');
  my $name = $c->param('name');
  # clean up user input
  $account =~ s/^\s+//;
  $account =~ s/\s+$//;
  $account =~ s/^@//;
  $c->render(template => 'follow_confirm', name => $name, account => $account);
} => 'follow_confirm';

get '/auth' => sub {
  my $c = shift;
  my $account = $c->param('account');
  my $action = $c->param('action');
  my $name = $c->param('name');
  my $logging = $c->param('logging');
  app->log->debug("$account wants to authorize the '$action' action for the $name list")
      if $logging;
  $c->cookie(account => $account, {expires => time + 60});
  $c->cookie(action => $action, {expires => time + 60});
  $c->cookie(name => $name, {expires => time + 60});
  $c->cookie(logging => $logging, {expires => time + 60});
  my $client = client($c, $account, $logging);
  return unless $client;
  # workaround for Mastodon::Client 0.015
  my $instance = (split('@', $account, 2))[1];
  my $url = $client->authorization_url(instance => $instance);
  $url =~ s/client_id=[a-zA-Z0-9]+/client_id=XXX/;
  app->log->debug("$account is being redirected to $url")
      if $logging;
  $c->redirect_to($client->authorization_url(instance => $instance));
} => 'auth';

sub load_credentials {
  my $where = shift;
  my $file = "$dir/credentials";
  if (open(my $fh, "<", $file)) {
    while (my $line = <$fh>) {
      next unless $line;
      my ($instance, $client_id, $client_secret) = split(" ", $line);
      return ($instance, $client_id, $client_secret) if $instance eq $where;
    }
  }
}

sub save_credentials {
  my $file = "$dir/credentials";
  open(my $fh, ">>", $file) || die "Cannot append to $file: $!";
  print $fh join(" ", @_) . "\n";
  close($fh) || die "Cannot close $file: $!";
}

sub client {
  my $c = shift;
  my $account = shift;
  my $logging = shift;
  my ($who, $where) = split(/@/, $account);
  if (not $where) {
    return error($c, "Account must look like an email address, "
		 . 'e.g. kensanata@octodon.social');
  }

  # set up client attributes
  my %attributes = (
    instance	    => $where,
    redirect_uri    => app->config('uri'),
    scopes          => ['follow', 'read', 'write'],
    name	    => 'Trunk',
    website	    => app->config('uri'), );

  my ($instance, $client_id, $client_secret) = load_credentials($where);

  my $client;
  if ($instance) {
    app->log->debug("$account found client credentials for $instance: "
		. "id " . ($client_id ? "yes" : "no") . ", "
		. "secret " . ($client_secret ? "yes" : "no"))
	if $logging;
    $attributes{client_id}     = $client_id;
    $attributes{client_secret} = $client_secret;
    $client = Mastodon::Client->new(%attributes);
  } else {
    app->log->debug("$account found no client credentials for $where")
	if $logging;
    $client = Mastodon::Client->new(%attributes);
    $client->register();
    $instance = $client->instance->uri;
    $instance =~ s!^https://!!;
    $client_id = $client->client_id;
    $client_secret = $client->client_secret;
    app->log->debug("$account registered client and got new credentials for $instance: "
		. "id " . ($client_id ? "yes" : "no") . ", "
		. "secret " . ($client_secret ? "yes" : "no"))
	if $logging;
    save_credentials($instance, $client->client_id, $client->client_secret);
  }
  app->log->debug("$account has a client: " . ($client ? "yes" : "no"))
      if $logging;
  return $client;
}

sub follow {
  my $client = shift;
  my $list_id = shift;
  my $acct = shift;
  my $account;

  eval { $account = $client->remote_follow($acct) };
  return "Could not follow $acct" if $@;

  eval { $client->post("lists/$list_id/accounts" => {account_ids => [$account->{id}]}) };
  return "Could not add $acct to the list" if $@;

  return "Followed $acct";
}

get 'do/follow' => sub {
  my $c = shift;

  my $code = $c->param('code')
      || return error($c, "We failed to get an authorization code.");

  my $account = $c->param('account')
      || return error($c, "We did not find the account in the cookie.");

  my $name = $c->param('name')
      || return error($c, "We did not find the list name in the cookie.");

  my $logging = $c->param('logging'); # optional

  my $client = client($c, $account, $logging) || return;

  # We don't save the access_token returned by this call!
  eval {
    app->log->debug("$account authorizing using a code: " . ($code ? "yes" : "no"))
	if $logging;
    $client->authorize(access_code => $code);
  };
  if ($@) {
    return error($c, "Authorisation failed. Did you try to reload the page? "
		 . "This will not work since we're not saving the access token.");
  }

  # Create the list and add the new accounts we're following to the new list, if
  my $list = $client->post('lists', {title => $name});
  if ($@) {
    return error("List creation of $name failed");
  }
  my $list_id = $list->{id};

  # get the new accounts we're supposed to follow (strings)
  my $path = Mojo::File->new("$dir/$name.txt");
  my @accts = split(" ", $path->slurp);

  # work in parallel and gather results
  app->log->debug("$account begins to follow " . scalar(@accts) . " accounts from list $name")
      if $logging;
  my @results = mce_loop {
    MCE->gather(follow($client, $list_id, $_));
  } @accts;

  # done
  app->log->debug("$account followed " . scalar(@results) . " accounts from list $name")
      if $logging;
  $c->render(template => 'follow_done',
	     name => $name,
	     results => \@results);
} => 'do_follow';


get '/logo' => sub {
  my $c = shift;
  $c->reply->file("$dir/trunk-logo.png");
};


get '/index.md' => sub {
  my $c = shift;
  $c->reply->file("$dir/index.md");
};


get '/admin' => sub {
  my $c = shift;
  $c->render();
};

get '/help' => sub {
  my $c = shift;
  my $md = to_markdown('help.md');
  $c->render(template => 'markdown',
	     title => "Trunk Help",
	     md => $md);
};

get '/others' => sub {
  my $c = shift;
  my $md = to_markdown('others.md');
  $c->render(template => 'markdown',
	     title => "Other Sites",
	     md => $md);
};

sub administrators {
  my $file = 'index.md';
  my $path = Mojo::File->new("$dir/$file");
  my $text = decode_utf8($path->slurp) || die "Cannot open $dir/$file: $!";
  my @admins;
  while ($text =~ /^- \[(@\S+)\]/mg) {
    push(@admins, $1);
  }
  return \@admins;
}

get '/request' => sub {
  my $c = shift;
  my $md = to_markdown('request.md');
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <"$dir"/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(template => 'request_add',
	     md => $md,
	     lists => \@lists);
};

get 'do/request' => sub {
  my $c = shift;
  my $account = $c->param('account');
  $account =~ s/^\s+//; # trim leading whitespace
  $account =~ s/\s+$//; # trim trailing whitespace
  $account =~ s/^@//;   # trim extra @ at the beginning
  $account =~ s!^https://([^/]+)/@([^/]+)$!$2\@$1!; # URL format
  my ($username, $instance) = split(/@/, $account);
  my $hash = $c->req->query_params->to_hash;
  delete $hash->{account};
  my @lists = sort { lc($a) cmp lc($b) } keys %$hash;
  local $" = ", ";
  my $admins = administrators();
  my $lucky = $admins->[int(rand(@$admins))];
  my $text = url_escape("$lucky Please add me to @lists. #Trunk");
  my $url = "https://$instance/share?text=$text";
  $c->render(template => 'request_done',
	     url => $url);
} => 'do_request';

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
      return undef unless $username and $password;
      if (app->config('users')->{$username}
	  && $password eq app->config('users')->{$username}) {
	return $username;
      }
      return undef;
    },
};


get '/login' => sub {
  my $c = shift;
  my $action = $c->param('action');
  my $username = $c->param('username');
  my $password = $c->param('password');
  $c->stash(login => '');
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


get "/logout" => sub {
  my $self = shift;
  $self->logout();
  $self->redirect_to('index');
} => 'logout';


get '/log' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'log'));
  }
  my $path = Mojo::File->new($log->path);
  my @lines = split(/\n/, decode_utf8($path->slurp));
  my $n = @lines < 30 ? @lines : 30;
  $c->render(log => join("\n", @lines[-$n .. -1]));
};


get '/log/all' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'log'));
  }
  my $path = Mojo::File->new($log->path);
  $c->render(text => decode_utf8($path->slurp), format => 'txt');
} => 'log_all';


get '/add' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'add'));
  }
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <"$dir"/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(template => 'add', lists => \@lists);
};


sub backup {
  my $path = shift;
  my @backups = <"$path".~*~>;
  my $i = 1;
  for (@backups) {
    my ($n) = /\.~(\d+)~$/;
    $i = $n + 1 if $n > $i;
  }
  $path->copy_to("$path.~$i~");
}

sub add_account {
  my $path = shift;
  my $account = shift;
  return 0 unless -e $path;
  my %accounts = map { $_ => 1 } split(" ", $path->slurp);
  if (not $accounts{$account}) {
    backup($path);
    my $fh = $path->open(">>:encoding(UTF-8)") || die "Cannot write to $path: $!";
    print $fh "$account\n";
    close($fh);
    return 1;
  }
  # already exists
  return 2;
}

post '/do/add' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'add'));
  }
  my $user = $c->current_user->{username};
  my $account = $c->param('account');
  if (!$account && $c->param('message')
      && $c->param('message') =~ /@(\S+@\S+)/) {
    $account = $1;
  }
  $account =~ s/^\s+//; # trim leading whitespace
  $account =~ s/\s+$//; # trim trailing whitespace
  $account =~ s/^@//;   # trim extra @ at the beginning
  $account =~ s!^https://([^/]+)/@([^/]+)$!$2\@$1!; # URL format
  return error($c, "Please provide an account.") unless $account;
  return error($c, "'$account' doesn't look like a good account name")
      unless $account =~ /^\S+\@\S+$/i;
  my $hash = $c->req->body_params->to_hash;
  delete $hash->{account};
  delete $hash->{message};
  delete $hash->{dequeue};
  delete $hash->{id};
  my @lists = sort { lc($a) cmp lc($b) } keys %$hash;
  if ($c->param('message')
      && $c->param('message') =~ /Please add me to ([^.]+)\./) {
    push(@lists, split(/,\s+/, $1));
  }
  my @good;
  my @bad;
  for my $name (@lists) {
    $name =~ s/&amp;/&/g;
    if (add_account(Mojo::File->new("$dir/$name.txt"), $account)) {
      push(@good, $name);
    } else {
      push(@bad, $name);
    }
  }
  local $" = ", ";
  $log->info("$user added $account to @good") if @good;
  $log->warn("$user tried to add $account to @bad but failed") if @bad;

  if ($c->param('dequeue')) {
    my $id = $c->param('id');
    delete_from_queue($c, $account);
    bot_reply($c, $account, $id, \@good, \@bad);
  }

  $c->render(template => 'do_add', account => $account, good => \@good, bad => \@bad);
} => 'do_add';


sub bot_reply {
  my $c = shift;
  my $account = shift;
  my $id = shift;
  my $good = shift;
  my $bad = shift;

  my $bot = app->config('bot');
  if (not $bot) {
    app->log->debug('No bot configured');
    return;
  }

  my $client_path = Mojo::File->new("$dir/$bot.client");
  my $user_path = Mojo::File->new("$dir/$bot.user");
  if (not -e $client_path or not -e $user_path) {
    app->log->debug("$bot.client and $bot.user files must exist");
    return;
  }

  my ($client_id, $client_secret) = split(' ', $client_path->slurp);
  my ($access_token) = split(' ', $user_path->slurp);

  $log->debug("$bot is missing client id") unless $client_id;
  $log->debug("$bot is missing client secret") unless $client_secret;
  $log->debug("$bot is missing access token") unless $access_token;
  $log->debug("$bot has access token") if $access_token;

  my ($name, $instance) = split(/\@/, $bot);
  my $client = Mastodon::Client->new(
    instance        => $instance,
    name            => $name,
    client_id       => $client_id,
    client_secret   => $client_secret,
    access_token    => $access_token);

  my $text = '@' . $account;
  local $" = ", ";
  $text .= " Done! Added you to @$good." if @$good;
  $text .= " Sadly, these don't exist: @$bad." if @$bad;
  $text .= " 🐘";

  my $params = {
    in_reply_to_id => $id,
    visibility	   => 'direct',
  };

  eval {
    $client->post_status($text, $params);
    $log->debug("$bot sent a direct message: $text");
  };
  if ($@) {
    $log->error("$bot was unable to reply [$text]: $@");
  }
}


get '/remove' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'remove'));
  }
  my $account = $c->param('account');
  $c->render(template => 'remove', account => $account);
};


sub remove_account {
  my $path = shift;
  my $account = shift;
  my @accounts = split(" ", $path->slurp);
  for (my $i = 0; $i <= $#accounts; $i++) {
    if ($accounts[$i] eq $account) {
      backup($path);
      splice(@accounts, $i, 1);
      $path->spurt(encode_utf8(join("\n", @accounts, "")));
      return 1;
    }
  }
  return 0;
}

any '/do/remove' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'remove'));
  }
  my $user = $c->current_user->{username};
  my $account = $c->param('account');
  $account =~ s/^\s+//; # trim leading whitespace
  $account =~ s/\s+$//; # trim trailing whitespace
  $account =~ s/^@//;   # trim extra @ at the beginning
  $account =~ s!^https://([^/]+)/@([^/]+)$!$2\@$1!; # URL format
  $log->info("$user removed $account");
  my @lists;
  for my $file (<"$dir"/*.txt>) {
    next unless -s $file;
    my $path = Mojo::File->new($file);
    my $name = $path->basename('.txt');
    push(@lists, $name) if remove_account($path, $account);
  }
  if (@lists) {
    $c->render(template => 'do_remove', account => $account, lists => \@lists);
  } else {
    $c->render(template => 'do_remove_failed', account => $account);
  }
} => 'do_remove';


get '/search' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'search'));
  }
  $c->render(template => 'search');
};


post '/do/search' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'search'));
  }
  my $account = $c->param('account');
  $account =~ s/^\s+//; # trim leading whitespace
  $account =~ s/\s+$//; # trim trailing whitespace
  $account =~ s/^@//; # trim leading @
  return error($c, "Please provide an account.") unless $account;
  my %accounts;
  for my $file (<"$dir"/*.txt>) {
    next unless -s $file;
    my $path = Mojo::File->new($file);
    my $name = $path->basename('.txt');
    for my $account (grep(/$account/i, split(" ", $path->slurp))) {
      push(@{$accounts{$account}}, $name);
    }
  }
  if (keys %accounts) {
    $c->render(template => 'do_search', accounts => \%accounts);
  } else {
    $c->render(template => 'do_search_failed', account => $account);
  }
} => 'do_search';




get '/blacklist' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'blacklist'));
  }
  my $md = to_markdown('blacklist.md');
  $c->render(template => 'markdown',
	     title => "Trunk Blacklist",
	     md => $md);
} => 'blacklist';



get '/create' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'create'));
  }
  $c->render(template => 'create');
};


post '/do/list' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'create'));
  }
  my $user = $c->current_user->{username};
  my $name = $c->param('name');
  return error($c, "Please provide a list name.") unless $name;
  $name =~ s/^\s+//; # trim leading whitespace
  $name =~ s/\s+$//; # trim trailing whitespace

  my $path = Mojo::File->new("$dir/$name.txt");
  return error($c, "This list already exists.") if -e $path;

  $log->info("$user created $name");
  my $fh = $path->open(">>:encoding(UTF-8)")
      || error($c, "Cannot write to $path: $!");
  close($fh);

  $c->render(template => 'do_create', name => $name);
} => 'do_create';


get '/rename' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'rename'));
  }
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <"$dir"/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(template => 'rename', lists => \@lists);
};


post '/do/rename' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'rename'));
  }

  my $user = $c->current_user->{username};

  my $old_name = $c->param('old_name');
  return error($c, "Please pick a list to rename.") unless $old_name;

  my $old_path = Mojo::File->new("$dir/$old_name.txt");
  return error($c, "This list does not exists.") if not -e $old_path;

  my $new_name = $c->param('new_name');
  return error($c, "Please provide a new list name.") unless $new_name;
  $new_name =~ s/^\s+//; # trim leading whitespace
  $new_name =~ s/\s+$//; # trim trailing whitespace

  my $new_path = Mojo::File->new("$dir/$new_name.txt");
  return error($c, "This list already exists.") if -e $new_path;

  eval {
    $old_path->move_to($new_path);
    $log->info("$user renamed $old_name to $new_name");
  };
  if ($@) {
    $log->info("$user tried to rename $old_name to $new_name: $@");
    return error($c, "Renaming this list failed. Most likely because the new name contained a slash"
		 . " or some other illegal character in filenames");
  }

  my $old_desc = Mojo::File->new("$dir/$old_name.md");
  if (-e $old_desc) {
    my $new_desc = Mojo::File->new("$dir/$new_name.md");
    unlink($new_desc) if -e $new_desc;
    eval {
      $new_path = $old_desc->move_to($new_desc);
    };
    if ($@) {
      $log->info("$user tried to rename the $old_name list description to $new_name: $@");
    }
  }

  $c->render(template => 'do_rename', old_name => $old_name, new_name => $new_name);
} => 'do_rename';


get '/describe' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'describe'));
  }
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <"$dir"/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(template => 'describe', lists => \@lists);
};


post '/do/describe' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'describe'));
  }

  my $user = $c->current_user->{username};

  my $name = $c->param('name');
  return error($c, "Please pick a list to describe.") unless $name;

  my $description = $c->param('description');

  my $list = -e Mojo::File->new("$dir/$name.txt");
  my $path = Mojo::File->new("$dir/$name.md");

  if ($description) {

    backup($path) if -e $path;
    $log->info("$user described $name");
    $path->spurt(encode_utf8($description));
    $c->render(template => 'do_describe', name => $name,
	       description => $description, saved => 1, list => $list);

  } else {

    $description = decode_utf8($path->slurp) if -e $path;
    $c->render(template => 'do_describe', name => $name,
	       description => $description, saved => 0, list => $list);

  }
} => 'do_describe';

get '/overview' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'overview'));
  }
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <"$dir"/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(template => 'overview', lists => \@lists);
};

sub overview {
  # HACK ALERT: plenty of shortcuts here which might only work for Mastodon...
  my $ua = Mojo::UserAgent->new->connect_timeout(3)->request_timeout(5);
  my $account = shift;
  $log->debug("start working on $account");
  my ($username, $domain) = split "@", $account;
  my $result;
  # We should get the first URL from here, looking at the "aliases" key:
  # curl "https://octodon.social/.well-known/webfinger?resource=acct%3Akensanata%40octodon.social"
  my $url = "https://$domain/users/$username";
  my %obj = (id => $account, url => $url, bio => '', published => '');
  eval {
    $result = $ua->max_redirects(2)->get($url => {Accept => "application/json"})->result;
  };
  if ($@) {
    $obj{bio} = "<p>Error: $@</p>";
    $log->warn("$url $@");
    return \%obj;
  }
  if (not $result->is_success) {
    $obj{bio} = "<p>" . $result->code . ": " . $result->message . "</p>";
    $log->warn("$url result " . $result->code . ": " . $result->message);
    return \%obj;
  }
  $obj{bio} = $result->json->{summary}
    if $result->json->{summary};
  my $outbox = $result->json->{outbox};
  # We should get this URL from the previous one:
  # curl -H 'Accept: application/json' https://octodon.social/users/kensanata
  # gives us the "outbox" key and the value is a URL which we can fetch again
  # curl https://octodon.social/users/kensanata/outbox
  # and that gives us a short description including the "first" key which gives us a bunch of statuses
  # and we just look at the first one
  $url = "$outbox?page=true";
  eval {
    $result = $ua->max_redirects(2)->get($url => {Accept => "application/json"})->result;
  };
  if ($@) {
    $obj{published} = "<p>Error: $@</p>";
    $log->warn("$url error $@");
    return \%obj;
  }
  if (not $result->is_success) {
    $obj{published} = "<p>" . $result->code . ": " . $result->message . "</p>";
    $log->warn("$url result " . $result->code . ": " . $result->message);
    return \%obj;
  }
  $obj{published} = $result->json->{orderedItems}->[0]->{published}
    if $result->json->{orderedItems}->[0]->{published};
  $log->debug("end working on $account");
  return \%obj;
}

app->minion->add_task(overview => sub {
  my ($job, $account) = @_;
  $job->finish(overview $account) });

get '/do/overview' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'overview'));
  }

  my $name = $c->param('name');
  return error($c, "Please pick a list for the overview.") unless $name;

  my $path = Mojo::File->new("$dir/$name.txt");
  return error($c, "Please pick an existing list.") unless -e $path;

  my @accounts = split(" ", $path->slurp);
  return error($c, "$name is an empty list.") unless @accounts;

  my @ids = map { $c->app->minion->enqueue(overview => [$_]) } @accounts;

  my %jobs;
  my $worker = $c->app->minion->repair->worker->register;
  do {
    for my $id (keys %jobs) {
      delete $jobs{$id} if $jobs{$id}->is_finished;
    }
    if (keys %jobs >= 40) { sleep 1 }
    else {
      my $job = $worker->dequeue(1);
      $jobs{$job->id} = $job->start if $job;
    }
  } while keys %jobs;
  $worker->unregister;

  my @results = map { $c->app->minion->job($_)->info->{result} } @ids;
  $c->render(template => 'do_overview', name => $name, accounts => \@results);
} => 'do_overview';


get '/api/v1/list' => sub {
  my $c = shift;
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <"$dir"/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(json => \@lists);
};

get '/api/v1/list/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  $name =~ s/\+/ /g; # hack: fix broken clients
  my $path = Mojo::File->new("$dir/$name.txt");
  my @accounts = map { { acct => $_ } } sort { lc($a) cmp lc($b) } split(" ", $path->slurp);
  $c->render(json => \@accounts);
};



sub load_queue {
  my $path = Mojo::File->new("$dir/queue");
  return decode_json $path->slurp if -e $path;
  return [];
}

sub save_queue {
  my $queue = shift;
  my $path = Mojo::File->new("$dir/queue");
  $path->spurt(encode_json $queue);
}

sub delete_from_queue {
  my $c = shift;
  my $acct = shift;
  my $user = $c->current_user->{username};

  my $i = 0;
  my $change = 0;
  my $queue = load_queue();

  while ($i < @$queue) {
    if ($queue->[$i]->{acct} eq $acct) {
      splice(@$queue, $i, 1);
      $log->info("$user removed $acct from queue");
      $change = 1;
    } else {
      $i++;
    }
  }

  save_queue($queue);
  return $change;
}

sub add_to_queue {
  my $c = shift;
  my $acct = shift;
  my $id = shift;
  my $names = shift;
  my $user = $c->current_user->{username};
  my $queue = load_queue();
  push(@$queue, {acct => $acct, id => $id, names => $names});
  save_queue($queue);
  $log->info("$user enqueued $acct for @$names");
}

get '/api/v1/queue' => sub {
  my $c = shift;
  $c->authenticate($c->param('username'), $c->param('password'));
  return error($c, "Must be authenticated") unless $c->is_user_authenticated();
  $c->render(json => load_queue());
};

post '/api/v1/queue' => sub {
  my $c = shift;
  $c->authenticate($c->param('username'), $c->param('password'));
  return error($c, "Must be authenticated") unless $c->is_user_authenticated();
  my $acct = $c->param('acct');
  return error($c, "Missing acct parameter") unless $acct;
  my $id = $c->param('id');
  return error($c, "Missing id parameter") unless $id;
  my $names = $c->every_param('name');
  return error($c, "Missing name parameter") unless @$names;
  delete_from_queue($c, $acct);
  add_to_queue($c, $acct, $id, $names);
  $c->render(text => 'OK');
};

del '/api/v1/queue' => sub {
  my $c = shift;
  return error($c, "Must be authenticated") unless $c->is_user_authenticated();
  my $acct = $c->param('acct');
  return error($c, "Missing acct parameter") unless $acct;
  if (delete_from_queue($c, $acct)) {
    $c->render(text => 'OK');
  } else {
    $c->render(text => "$acct not found", status => '404');
  }
};

get '/queue' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'queue'));
  }
  $c->render(template => 'queue', queue => load_queue());
};

get '/queue/delete' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'queue'));
  }
  my $acct = $c->param('acct') || return error($c, "Missing acct parameter");
  if (delete_from_queue($c, $acct)) {
    $c->render(template => 'queue_delete', acct => $acct);
  } else {
    error($c, "$acct not found in the queue");
  }
} => 'queue_delete';

app->defaults(layout => 'default');
app->start;

__DATA__


@@ index.html.ep
% title 'Trunk for the Fediverse';
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


@@ follow.html.ep
% title 'Login to Mastodon Instance';
<h1>Which account to use?</h1>

<p>Please provide the account you want to use. Do not provide your email
address: I'd use <em>kensanata@octodon.social</em> instead of
<em>kensanata@gmail.com</em>, for example. You will be redirected to your
instance. There, you need to authorize the Trunk application to act on your
behalf. If you do, Trunk will proceed to follow <%= link_to grab => {name =>
$name} => begin%><%= $name %><%= end %>. If you prefer not to do that, no
problem. Just go back to the list and go through the list manually.</p>

%= form_for follow_confirm => begin
%= text_field 'account', required => undef
%= hidden_field name => $name
%= submit_button
% end


@@ follow_confirm.html.ep
% title 'Confirmation';
<h1>Please confirm</h1>

<p>We're going to use <em><%= $account %></em> to follow all the accounts in <%=
link_to grab => {name => $name} => begin%><%= $name %><%= end %>.</p>

<p><%= link_to url_for('auth')->query(account => $account, action => 'follow',
name => $name) => (class => 'button') => begin %>Let's do this<% end %></p>

<p>If you'd like to help us find the
<a href="https://alexschroeder.ch/software/Client_authentication_failed">authorisation problems</a>
we've been having, please use the following link instead:</p>

<p><%= link_to url_for('auth')->query(account => $account, action => 'follow',
logging => 'ok', name => $name) => (class => 'button') => begin %>Let's log
this<% end %></p>



@@ grab.html.ep
% title 'Grab a List';
<h1><%= $name %></h1>

<%== $description %>

<%== $md %>

% if ($mass_follow) {
<p class="needspace">
<%= link_to url_for('follow')->query(name => $name) => (class => 'button') => begin %>Follow <%= $name %><% end %>
</p>
% }

<ul class="follow">
% for my $account (@$accounts) {
<li>
% my ($username, $instance) = split(/@/, $account);
<a href="https://<%= $instance %>/users/<%= $username %>/remote_follow" class="button">Follow</a>
<a href="https://<%= $instance %>/users/<%= $username %>">
%= $account
</a>
</li>
% }
</ul>


@@ follow_done.html.ep
% title 'Follow a List';
<h1><%= $name %></h1>

<p>We created the <em><%= $name %></em> list for you. Note that if you visit
this list in the Mastodon web client, it will appear empty. In fact, this is
what it will say:</p>

<blockquote>"There is nothing in this list yet. When members of this list post
new statuses, they will appear here."</blockquote>

<p>Click on the button with the three sliders ("Show settings") and then on
"Edit lists" and only then will you see the people in the list!</p>

<P>Enjoy! 👍</p>

<p>Results:</p>

<ul>
% for my $result (@$results) {
<li><%= $result %></li>
% }
</ul>


@@ request_add.html.ep
% title 'Request List Membership';
<%== $md %>

%= form_for do_request => begin
%= label_for account => 'Account'
%= text_field 'account', required => undef

<p>
% for (@$lists) {
<label><%= check_box $_ %><%= $_ %></label>
% };
</p>

%= submit_button 'Add Me', class => 'button'
% end


@@ request_done.html.ep
% title 'Request List Membership';
<h1>Please confirm</h1>

<p>OK, ready? If you click the link below, you should get sent to your instance,
your request ready to toot. 📯</p>

<p><%= link_to $url => (class => 'button') => begin %>Add Me<% end %></p>


@@ admin.html.ep
% title 'Trunk Admins';
<h1>Administration</h1>

<p>Hello and thank you for helping administrate the Trunk lists! The following
tasks all require you to be logged in. Please note that admin actions will be
logged, just in case.</p>

<ul>
<li><%= link_to 'Search an account' => 'search' %></li>
<li><%= link_to 'Add an account' => 'add' %></li>
<li><%= link_to 'Remove an account' => 'remove' %></li>
<li><%= link_to 'Create a list' => 'create' %></li>
<li><%= link_to 'Rename a list' => 'rename' %></li>
<li><%= link_to 'Describe a list' => 'describe' %></li>
<li><%= link_to 'Overview of a list' => 'overview' %></li>
<li><%= link_to 'Check the queue' => 'queue' %></li>
<li><%= link_to 'Check the log' => 'log' %></li>
<li><%= link_to 'Logout' => 'logout' %></li>
</ul>


@@ log.html.ep
% title 'Log';
<h1>Log</h1>

<p>
<%= link_to 'View entire log file' => 'log_all' %>.
</p>

<p>
This is currently the end of the log file:
</p>

<pre>
%= $log
</pre>


@@ add.html.ep
% title 'Add an account';
<h1>Add an account</h1>

<p>Their request, e.g.:</p>

<blockquote>
<p>Alex Schroeder 🐝 @kensanata@octodon.social</p>
<p>@eloisa Please add me to Digital Rights, FLOSS, Mastodon, Privacy. #Trunk</p>
</blockquote>

%= form_for do_add => begin
%= text_area 'message'

<p>If you paste a request like the one above, you're done.</p>

%= submit_button

<p>Alternatively, provide the account here. You can either provide the URL to
the account (such as <em>https://octodon.social/@kensanata</em>) or the account
itself (such as <em>kensanata@gmail.com</em>).</p>

%= label_for account => 'Account'
%= text_field 'account'

<p>
%= link_to 'Create a list' => 'create'
%= link_to 'Check blacklist' => 'blacklist'
</p>

<p>Lists:
% for (@$lists) {
<label><%= check_box $_ %><%= $_ %></label>
% };
</p>

%= submit_button
% end


@@ do_add.html.ep
% title 'Add an account';
<h1>Add an account</h1>

% if (@$good) {
<p>The account <%= $account %> was added to the following lists:
%= join(", ", @$good);
</p>
% }

% if (@$bad) {
<p>The account <%= $account %> was <strong>not added</strong> to the following
lists because they don't exist:
%= join(", ", @$bad);
</p>
% }

<p>
%= link_to 'Add another account' => 'add'
</p>


@@ remove.html.ep
% title 'Remove an account';
<h1>Remove an account</h1>

<p>This will remove an account from all the lists.</p>

<p>Both forms, <em>https://octodon.social/@kensanata</em> and
<em>kensanata@gmail.com</em> are accepted.</p>

%= form_for do_remove => begin
%= label_for account => 'Account'
%= text_field 'account', required => undef
%= submit_button
% end


@@ do_remove.html.ep
% title 'Remove an account';
<h1>Remove an account</h1>

<p>The account <%= $account %> was removed from the following lists:
%= join(", ", @$lists);
</p>

<p>
%= link_to 'Remove another account' => 'remove'
or
<%= link_to url_for('add')->query(account => $account, map { $_ => 'on' } @$lists) => begin %>add some of it back again<% end %>
</p>


@@ do_remove_failed.html.ep
% title 'Remove an account';
<h1>Account not found</h1>

<p>The account <%= $account %> was not found on any list.</p>

<p>
%= link_to 'Remove a different account' => 'remove'
</p>


@@ search.html.ep
% title 'Search for an account';
<h1>Search for an account</h1>

<p>This is where you search for accounts to see if they are already in any of
the lists.</p>

%= form_for do_search => begin
%= label_for account => 'Account'
%= text_field 'account', required => undef
%= submit_button
% end


@@ do_search.html.ep
% title 'Search for an account';
<h1>Search for an account</h1>

<p>Clicking on the account links on this page will allow you to "edit" an
account: first you remove them from all their lists and then you add some of it
back again, using a different account if they changed their instance or by
changing the lists they belong to.</p>

<ul>
% for my $account (keys %$accounts) {
<li>
<%= link_to url_for('remove')->query(account => $account) => begin %><%= $account %><% end %>
currently belongs to <%= join(", ", @{$accounts->{$account}}) %>
</li>
% }
</ul>


<p>
%= link_to 'Search another account' => 'search'
or
%= link_to 'add an account' => 'add'
</p>


@@ do_search_failed.html.ep
% title 'Search an account';
<h1>Account not found</h1>

<p>The account <%= $account %> was not found on any list.</p>

<p>
%= link_to 'Search a different account' => 'search'
</p>


@@ create.html.ep
% title 'Create a list';
<h1>Create a list</h1>

%= form_for do_create => begin
%= label_for name => 'List'
%= text_field 'name', required => undef
%= submit_button
% end


@@ do_create.html.ep
% title 'Create a list';
<h1>Create a list</h1>

<p>The list <em><%= $name %></em> was created.</p>

<p>
<%= link_to url_for('describe')->query(name => $name) => begin %>Describe this list<% end %>,
%= link_to 'add another list' => 'create'
or
%= link_to 'add an account' => 'add'
</p>


@@ rename.html.ep
% title 'Rename a list';
<h1>Rename a list</h1>

<p>
%= link_to 'Create a list' => 'create'
instead
</p>

%= form_for do_rename => begin
%= label_for new_name => 'New Name'
%= text_field 'new_name', required => undef

<p>List to rename:
% for my $name (@$lists) {
<label><%= radio_button old_name => $name %><%= $name %></label>
% }
</p>

%= submit_button
% end


@@ do_rename.html.ep
% title 'Create a list';
<h1>Rename a list</h1>

<p>The list <em><%= $old_name %></em> was renamed to <em><%= $new_name %></em>.</p>

<p>
<%= link_to url_for('rename')->query(old_name => $new_name) => begin %>Rename it again<% end %>
or
%= link_to 'add an account' => 'add'
</p>


@@ describe.html.ep
% title 'Describe a list';
<h1>Describe a list</h1>

%= form_for do_describe => begin

<p>List to describe:
% for my $name (@$lists) {
<label><%= radio_button name => $name %><%= $name %></label>
% }
</p>

<p>Special descriptions:
<label><%= radio_button name => "index" %>the front page</label>,
<label><%= radio_button name => "help" %>the help page</label>,
<label><%= radio_button name => "request" %>the request to join</label>,
<label><%= radio_button name => "others" %>the links to other lists</label>,
<label><%= radio_button name => "blacklist" %>the blacklist</label>,
and
<label><%= radio_button name => "grab" %>the intro to the grab page</label>.
</p>

%= submit_button
% end


@@ do_describe.html.ep
% title 'Describe a list';
<h1>Describe <%= $name %></h1>

% if ($saved) {
<p>Description saved.
% if ($list) {
<%= link_to $c->url_for('grab', {name => $name}) => begin %>Check it out<% end %>.
% } elsif ($name eq 'grab') {
<%= link_to $c->url_for('grab', {name => 'Test'}) => begin %>Check it out<% end %>.
% } else {
<%= link_to $c->url_for($name) => begin %>Check it out<% end %>.
% }
</p>
% }

<p>This is where you can edit the description that goes at the top of the <%=
link_to $c->url_for('grab', {name => $name}) => begin %><%= $name %><% end %>
list. Please use Markdown. Feel free to link to Wikipedia, e.g.
<code>[Markdown](https://en.wikipedia.org/wiki/Markdown)</code>.</p>

%= form_for do_describe => begin
<p>
%= hidden_field name => $name
%= text_area 'description' => $description
</p>
<p>
%= submit_button
</p>
% end


@@ overview.html.ep
% title 'Overview over a list';
<h1>Overview over a  list</h1>

%= form_for do_overview => begin

<p>Choose list:
% for my $name (@$lists) {
<label><%= radio_button name => $name %><%= $name %></label>
% }
</p>

%= submit_button
% end


@@ do_overview.html.ep
% title 'Overview over a list';
<h1>Overview over a  list</h1>

<ul>
% for my $account(@$accounts) {
<li>
    %= link_to $account->{id} => $account->{url}
<%= link_to url_for('remove')->query(account => $account->{id}) => (class => 'button') => begin %>remove account<% end %>
<div class="bio">
%== $account->{bio}
</div>
<p class="published">
%== $account->{published}
</p>
%   if ($account->{movedTo}) {
%= link_to MOVED => $account->{movedTo}
%   }
% }
</ul>

@@ queue.html.ep
% title 'Queue';
<h1>Queue</h1>

% if (@$queue) {

<p>The current queue of additions:</p>

% while (my $item = shift @$queue) {

%= form_for do_add => begin
%= hidden_field 'dequeue' => 1
%= hidden_field 'account' => $item->{acct}
%= hidden_field 'id' => $item->{id}
% my ($username, $instance) = split(/@/, $item->{acct});
<p>
Add
<a href="https://<%= $instance %>/users/<%= $username %>">
%= $item->{acct}
</a>
to
% for (@{$item->{names}}) {
<label><%= check_box $_ => 1, checked => undef %><%= $_ %></label>
% };
</p>
<p>
Please take a look at their profile and check that the request makes sense. If
it does, you can accept their request by clicking the button below. This will
add them to all the lists they requested.
</p>
%= submit_button
<p>
If you disagree, however, you need to figure out whether this is spam or a
misunderstanding. If it is spam, just click the link below and delete the
request from the queue. If it is a misunderstanding, message them directly and
talk it over.
</p>
<%= link_to url_for('queue_delete')->query(acct => $item->{acct}) => begin %>Delete from queue<% end %>
%= link_to 'Check blacklist' => 'blacklist'
</p>

% if (@$queue > 0) {
<hr>
% }

% end

% }

% } else {

<p>The queue is empty. 😅</p>

<p>
%= link_to 'Back to the admin section' => 'admin'
</p>

% }

@@ queue_delete.html.ep
% title 'Queue';
<h1>Queue</h1>
<p>The account <%= $acct %> was deleted from the queue.</p>

<p>
<%= link_to url_for('search')->query(account => $acct) => begin %>Search for <%= $acct %><% end %>
%= link_to 'Back to the queue' => 'queue'
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
%= text_field 'username', required => undef
<p>
%= label_for password => 'Password'
%= password_field 'password', required => undef
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
Go back to the <%= link_to 'main menu' => 'index' %>.


@@ markdown.html.ep
<%== $md %>


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
  hyphens: auto;
}
p.needspace {
  margin: 20px 0;
}
.button {
  font-family: "DejaVu Sans", sans;
  font-size: 14pt;
  background: #2b90d9;
  color: #fff;
  padding: 10px;
  margin: 10px;
  border-radius: 4px;
  text-transform: uppercase;
  text-decoration: none;
  text-align: center;
  cursor: pointer;
  font-weight: 500;
  border: 0;
}
ul.follow { padding: 5px 0 }
.follow li { display: block; margin-bottom: 20pt;}
.logo { float: right; max-height: 300px; max-width:20%; }
.alert { font-weight: bold; }
.login label { display: inline-block; width: 12ex; }
.bio { font-size: smaller; }
.published { font-size: smaller; }
label { white-space:  nowrap; }
textarea { width: 100%; height: 10ex; font-size: inherit; }
input { font-size: inherit; }
@media only screen and (max-device-width: 600px) {
  body { padding: 0; }
  h1, p { padding: 0; margin: 5px 0; }
  ul, ol { margin: 0; }
  .follow li { white-space: nowrap; }
}
% end
<meta name="viewport" content="width=device-width">
</head>
<body lang="en">
%= image 'logo', alt => '', class => 'logo'
<%= content %>
<hr>
<p>
<a href="https://communitywiki.org/trunk">Trunk</a>&#x2003;
<a href="https://alexschroeder.ch/cgit/trunk/about/">Source</a>&#x2003;
<%= link_to 'Admins' => 'admin' %>&#x2003;
<%= link_to 'Help' => 'help' %>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
