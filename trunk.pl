#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::Cache;
use Text::Markdown 'markdown';
use File::Basename;
use File::Slurp;
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
  my @files = sort map {
    my ($name, $path, $suffix) = fileparse($_, '.txt');
    $name;
  } <$dir/*.txt>;
  $c->render(template => 'index', md => $md, files => \@files);
} => 'main';

get '/grab/:file' => sub {
  my $c = shift;
  my $name = $c->param('file');
  my @accounts = split(" ", read_file("$name.txt"));
  $c->render(template => 'grab', name => $name, accounts => \@accounts);
} => 'grab';

app->defaults(layout => 'default');
app->start;

__DATA__

@@ grab.html.ep
% title 'Grab a List';
<h1><%= $name %></h1>

<ul>
% for my $account (@$accounts) {
<li>
%= $account
</li>
% }
</ul>

@@ index.html.ep
% title 'Trunk for Mastodon';
<%== $md %>

<ul>
% for my $file (@$files) {
<li>
%= link_to grab => {file => $file} => begin
%= $file
% end
</li>
% }
</ul>


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
  font-family: "Palatino Linotype", "Book Antiqua", Palatino, serif;
}
% end
<meta name="viewport" content="width=device-width">
</head>
<body>
<%= content %>
<hr>
<p>
<a href="https://communitywiki.org/trunk">Trunk</a>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
