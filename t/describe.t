#!/usr/bin/env perl

# Copyright (C) 2019 Alex Schroeder <alex@gnu.org>

# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

use Test::More;
use Test::Mojo;
use Mojo::File;

require './trunk.pl';

my $t = Test::Mojo->new;

$t->get_ok('/describe')
    ->status_is(302)
    ->header_is('/login');

$t->ua->max_redirects(1);
$t->get_ok('/describe')
    ->status_is(200)
    ->text_is('h1' => 'Login')
    ->element_exists('form[action=/login]')
    ->element_exists('label[for=username]')
    ->element_exists('input[name=username][type=text]')
    ->element_exists('input[name=action][type=hidden][value=describe]');

$t->app->config({users=>{alex=>'let me in'}});

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'describe'})
    ->status_is(200)
    ->text_is('h1' => 'Describe a list')
    ->element_exists('form[action=/do/describe]')
    ->element_exists('label input[name=name][type=radio][value=Test]');

# create the list if it is missing
$path = Mojo::File->new('Test.txt');
$path->spurt("") if not -e $path;

# unlink the description
$path = Mojo::File->new('Test.md');
unlink($path) if -e $path;

$t->post_ok('/do/describe' => form => {
  name => 'Test' })
    ->status_is(200)
    ->text_is('h1' => 'Describe Test')
    ->content_like(qr'This is where you can edit the description');

$t->post_ok('/do/describe' => form => {
  name => 'Test',
  description => 'YOLO!',
  list => 1})
    ->status_is(200)
    ->text_is('h1' => 'Describe Test')
    ->content_like(qr'Description saved')
    ->element_exists('a[href=/grab/Test][text()=Check it out]');

ok(-e $path, "$path exists");
is($path->slurp, 'YOLO!');

my $c = $t->app->build_controller;

for my $page (qw(index help request others blacklist grab)) {

  # unlink the description of a special file
  $path = Mojo::File->new("$page.md");
  unlink($path) if -e $path;

  $t->post_ok('/do/describe' => form => {
    name => $page })
      ->status_is(200)
      ->text_is('h1' => "Describe $page")
      ->content_like(qr'This is where you can edit the description');

  my $url = $c->url_for($page);
  ok(length($url) > 0, "$page URL is $url");
  $url .= 'Test' if $url eq '/grab/';

  $t->post_ok('/do/describe' => form => {
    name => $page,
    description => 'Roll a d6!',
    list => 0})
      ->status_is(200)
      ->text_is('h1' => "Describe $page")
      ->content_like(qr'Description saved')
      ->element_exists("a[href=$url][text()=Check it out]");

  ok(-e $path, "$path exists");
  is($path->slurp, 'Roll a d6!', "$path saved");

  # make sure the URL is not bogus
  $t->get_ok($url)
      ->status_is(200)
      ->content_like(qr/Roll a d6!/);
}

done_testing();
