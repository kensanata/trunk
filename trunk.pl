#!/usr/bin/env perl
# Trunk is a web application to help find people in the Fediverse
# Copyright (C) 2018  Alex Schroeder <alex@gnu.org>
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
use Mojo::JSON qw(decode_json encode_json);
use Text::Markdown 'markdown';
use Encode qw(decode_utf8 encode_utf8);

my $dir = "/home/alex/src/trunk";            # FIXME
my $uri = "https://communitywiki.org/trunk"; # FIXME

my $log = Mojo::Log->new(path => "$dir/admin.log", level => 'debug');

plugin 'Config' => {default => {users => {}}};

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
  $c->render(template => 'error', msg => $msg, status => '500');
  return 0;
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
      return $c->redirect_to($url);
    } else {
      return error($c, "We got back an authorization code "
		   . "but the cookie was lost. This looks like a bug.");
    }
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
  my $description = to_markdown("$name.md");
  my $md = to_markdown('grab.md');
  $md =~ s/\$name_encoded/url_escape($name)/ge;
  $md =~ s/\$uri/$uri/ge;
  $md =~ s/\$name/$name/g;
  $c->render(template => 'grab', name => $name, accounts => \@accounts,
	     description => $description, md => $md);
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
  $c->cookie(account => $account, {expires => time + 60});
  $c->cookie(action => $action, {expires => time + 60});
  $c->cookie(name => $name, {expires => time + 60});
  my $client = client($c, $account);
  return unless $client;
  # workaround for Mastodon::Client 0.015
  my $instance = (split('@', $account, 2))[1];
  $c->redirect_to($client->authorization_url(instance => $instance));
} => 'auth';

sub client {
  my $c = shift;
  my $account = shift;
  my ($who, $where) = split(/@/, $account);
  if (not $where) {
    return error($c, "Account must look like an email address, "
		 . 'e.g. kensanata@octodon.social');
  }
  my ($instance, $client_id, $client_secret);

  # find the line in credentials matching our instance ("where")
  my $file = "$dir/credentials";
  if (open(my $fh, "<", $file)) {
    while (my $line = <$fh>) {
      next unless $line;
      ($instance, $client_id, $client_secret) = split(" ", $line);
      last if $instance eq $where;
    }
  }

  # set up client attributes
  my %attributes = (
    instance	    => $where,
    redirect_uri    => $uri,
    scopes          => ['follow', 'read', 'write'],
    name	    => 'Trunk',
    website	    => $uri, );

  my $client;
  if ($instance and $instance eq $where) {
    $attributes{client_id}     = $client_id;
    $attributes{client_secret} = $client_secret;
    $client = Mastodon::Client->new(%attributes);
  } else {
    $client = Mastodon::Client->new(%attributes);
    $client->register();
    open(my $fh, ">>", $file) || die "Cannot write $file: $!";
    $instance = $client->instance->uri;
    $instance =~ s!^https://!!;
    print $fh join(" ", $instance,
		   $client->client_id,
		   $client->client_secret) . "\n";
    close($fh) || die "Cannot close $file: $!";
  }
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

  my $client = client($c, $account) || return;

  # We don't save the access_token returned by this call!
  eval {
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
  my @results = mce_loop {
    MCE->gather(follow($client, $list_id, $_));
  } @accts;

  # done
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
  $c->render();
  my $md = to_markdown('request.md');
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <$dir/*.txt>) {
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
  $self->redirect_to('main');
} => 'logout';


get '/log' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'log'));
  }
  # we can't use $log->history because that might be empty after a restart
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
  # we can't use $log->history because that might be empty after a restart
  my $path = Mojo::File->new($log->path);
  $c->render(text => decode_utf8($path->slurp), format => 'txt');
} => 'log_all';


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


sub backup {
  my $path = shift;
  my $i = 1;
  while (-e "$path.~$i~") {
    $i++;
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
  my $hash = $c->req->body_params->to_hash;
  delete $hash->{account};
  delete $hash->{message};
  my @lists = sort { lc($a) cmp lc($b) } keys %$hash;
  if ($c->param('message')
      && $c->param('message') =~ /Please add me to ([^.]+)\./) {
    push(@lists, split(/,\s+/, $1));
  }
  my @good;
  my @bad;
  for my $name (@lists) {
    if (add_account(Mojo::File->new("$dir/$name.txt"), $account)) {
      push(@good, $name);
    } else {
      push(@bad, $name);
    }
  }
  local $" = ", ";
  $log->info("$user added $account to @good") if @good;
  $log->warn("$user tried to add $account to @bad but failed") if @bad;
  $c->render(template => 'do_add', account => $account, good => \@good, bad => \@bad);
} => 'do_add';


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
  for my $file (<$dir/*.txt>) {
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
  return error($c, "Please provide an account.") unless $account;
  my %accounts;
  for my $file (<$dir/*.txt>) {
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
  for my $file (sort { lc($a) cmp lc($b) } <$dir/*.txt>) {
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

  $log->info("$user renamed $old_name to $new_name");
  $new_path = $old_path->move_to($new_path);

  $c->render(template => 'do_rename', old_name => $old_name, new_name => $new_name);
} => 'do_rename';


get '/describe' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'describe'));
  }
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <$dir/*.txt>) {
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

  my $path = Mojo::File->new("$dir/$name.md");

  if ($description) {

    backup($path) if -e $path;
    $log->info("$user described $name");
    $path->spurt(encode_utf8($description));
    $c->render(template => 'do_describe', name => $name, description => $description, saved => 1);

  } else {

    $description = decode_utf8($path->slurp) if -e $path;
    $c->render(template => 'do_describe', name => $name, description => $description, saved => 0);

  }
} => 'do_describe';


get '/api/v1/list' => sub {
  my $c = shift;
  my @lists;
  for my $file (sort { lc($a) cmp lc($b) } <$dir/*.txt>) {
    my $name = Mojo::File->new($file)->basename('.txt');
    push(@lists, $name);
  }
  $c->render(json => \@lists);
};

get '/api/v1/list/:name' => sub {
  my $c = shift;
  my $name = $c->param('name');
  my $path = Mojo::File->new("$dir/$name.txt");
  my @accounts = map { { acct => $_ } } sort { lc($a) cmp lc($b) } split(" ", $path->slurp);
  $c->render(json => \@accounts);
};



get '/api/v1/queue' => sub {
  my $c = shift;
  my $path = Mojo::File->new("$dir/queue");
  return $c->render(json => []) unless -e $path;
  my $queue = decode_json $path->slurp;
  $c->render(json => $queue);
};

sub delete_from_queue {
  my $queue = shift;
  my $acct = shift;
  my $i = 0;
  my $change = 0;
  while ($i < @$queue) {
    if ($queue->[$i]->{acct} eq $acct) {
      splice(@$queue, $i, 1);
      $log->info("replaced $acct in queue");
      $change = 1;
    } else {
      $i++;
    }
  }
  return $change;
}

post '/api/v1/queue' => sub {
  my $c = shift;
  $c->authenticate($c->param('username'), $c->param('password'));
  return error($c, "Must be authenticated") unless $c->is_user_authenticated();

  my $acct = $c->param('acct');
  return error($c, "Missing acct parameter") unless $acct;

  my $names = $c->every_param('name');
  return error($c, "Missing name parameter") unless @$names;

  my $path = Mojo::File->new("$dir/queue");
  my $queue;
  $queue = decode_json $path->slurp if -e $path;

  delete_from_queue($queue, $acct);

  $log->info("enqueued $acct for @$names");
  push(@$queue, {acct => $acct, names => $names});
  $path->spurt(encode_json $queue);
  $c->render(text => 'OK');
};

del '/api/v1/queue' => sub {
  my $c = shift;
  return error($c, "Must be authenticated") unless $c->is_user_authenticated();
  my $acct = $c->param('acct');
  return error($c, "Missing acct parameter") unless $acct;
  $log->info("dequeued $acct");
  my $path = Mojo::File->new("$dir/queue");
  my $queue = decode_json $path->slurp;
  if (delete_from_queue($queue, $acct)) {
    $path->spurt(encode_json $queue);
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
  my $path = Mojo::File->new("$dir/queue");
  my $queue = decode_json $path->slurp;
  $c->render(template => 'queue', queue => $queue);
};

get '/queue/delete' => sub {
  my $c = shift;
  if (not $c->is_user_authenticated()) {
    return $c->redirect_to($c->url_for('login')->query(action => 'queue'));
  }
  my $acct = $c->param('acct') || return error($c, "Missing acct parameter");
  my $path = Mojo::File->new("$dir/queue");
  my $queue = decode_json $path->slurp;
  if (delete_from_queue($queue, $acct)) {
    $path->spurt(encode_json $queue);
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
%= text_field 'account'
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


@@ grab.html.ep
% title 'Grab a List';
<h1><%= $name %></h1>

<%== $description %>

<%== $md %>

<p class="needspace">
<%= link_to url_for('follow')->query(name => $name) => (class => 'button') => begin %>Follow <%= $name %><% end %>
</p>

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
%= text_field 'account'

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
%= text_field 'account'
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
%= text_field 'account'
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
%= text_field 'name'
%= submit_button
% end


@@ do_create.html.ep
% title 'Create a list';
<h1>Create a list</h1>

<p>The list <em><%= $name %></em> was created.</p>

<p>
%= link_to 'Add another list' => 'create'
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
%= text_field 'new_name'

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
<label><%= radio_button name => "request" %>the request to join</label>,
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
<%= link_to $c->url_for('grab', {name => $name}) => begin %>Check it out<% end %>.
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


@@ queue.html.ep
% title 'Queue';
<h1>Queue</h1>

% if (@$queue) {

<p>The current queue of additions:</p>

% for my $item (@$queue) {

%= form_for do_add => begin
%= hidden_field 'account' => $item->{acct}
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
%= submit_button
<p>
<%= link_to url_for('queue_delete')->query(acct => $item->{acct}) => begin %>Delete from queue<% end %>
</p>
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
.logo {float: right; max-height: 300px; max-width:20%; }
.alert { font-weight: bold; }
.login label { display: inline-block; width: 12ex; }
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
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
