#!/usr/bin/env perl

# Copyright (C) 2018–2022 Alex Schroeder <alex@gnu.org>

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
use utf8;

require './trunk.pl';

my $t = Test::Mojo->new;

$t->ua->max_redirects(1);

$t->app->config({users=>{alex=>'let me in'}});

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'create'})
    ->status_is(200)
    ->text_is('h1' => 'Create a list')
    ->element_exists('form[action=/do/list]');

$path = Mojo::File->new('Schröder.txt');
unlink($path) if -e $path;

$t->post_ok('/do/list' => form => { name => 'Schröder' })
    ->status_is(200)
    ->text_is('h1' => 'Create a list')
    ->content_like(qr'The list <em>Schröder</em> was created.');

ok(-e $path, 'Schröder.txt exists');

$path = Mojo::File->new('Schröder.md');
unlink($path) if -e $path;

$t->post_ok('/do/describe' => form => {
  name => 'Schröder',
  description => 'Schröder!',
  list => 1})
    ->status_is(200)
    ->text_is('h1' => 'Describe Schröder')
    ->content_like(qr'Description saved')
    ->text_is('[href=/grab/Schr%C3%B6der]' => 'Check it out');

$t->post_ok('/do/add' => form => {
  account => 'one@two',
  Schröder => 'on' })
    ->status_is(200)
    ->text_is('h1' => 'Add an account')
    ->content_like(qr'The account one@two was added to the following lists:\s+Schröder');

$path = Mojo::File->new('Schröder.txt');
is($path->slurp(), "one\@two\n", 'account saved');

done_testing();
