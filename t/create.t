#!/usr/bin/env perl

# Copyright (C) 2018 Alex Schroeder <alex@gnu.org>

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

$t->get_ok('/add_list')
    ->status_is(302)
    ->header_is('/login');

$t->ua->max_redirects(1);
$t->get_ok('/add_list')
    ->status_is(200)
    ->text_is('h1' => 'Login')
    ->element_exists('form[action=/login]')
    ->element_exists('label[for=username]')
    ->element_exists('input[name=username][type=text]')
    ->element_exists('input[name=action][type=hidden][value=add_list]');

$t->app->config({users=>{alex=>'let me in'}});

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'add_list'})
    ->status_is(200)
    ->text_is('h1' => 'Add a list')
    ->element_exists('form[action=/do/list]')
    ->element_exists('label[for=name]')
    ->element_exists('input[name=name][type=text]');

$path = Mojo::File->new('Test.txt');
unlink($path) if -e $path;

$t->post_ok('/do/list' => form => { name => 'Test' })
    ->status_is(200)
    ->text_is('h1' => 'Add a list')
    ->content_like(qr'The list <em>Test</em> was created.');

ok(-e $path, 'Test.txt exists');

done_testing();
