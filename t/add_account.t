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

# create empty list
$path = Mojo::File->new('Test.txt');
$path->spurt('');

my $t = Test::Mojo->new;

$t->get_ok('/add')
    ->status_is(302)
    ->header_is('/login');

$t->ua->max_redirects(1);
$t->get_ok('/add')
    ->status_is(200)
    ->text_is('h1' => 'Login')
    ->element_exists('form[action=/login]')
    ->element_exists('label[for=username]')
    ->element_exists('input[name=username][type=text]')
    ->element_exists('input[name=action][type=hidden][value=add]');

$t->app->config({users=>{alex=>'let me in'}});

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'add'})
    ->status_is(200)
    ->text_is('h1' => 'Add an account')
    ->element_exists('form[action=/do/add]')
    ->element_exists('label[for=account]')
    ->element_exists('input[name=account][type=text]')
    ->element_exists('input[name=Test][type=checkbox]');

$t->post_ok('/do/add' => form => { account => 'one', Test => 'on' })
    ->status_is(200)
    ->text_is('h1' => 'Add an account')
    ->content_like(qr'The account one was added to the following lists:\s+Test');

is($path->slurp(), "one\n", 'account saved');

$path2 = Mojo::File->new('Test2.txt');
unlink($path2) if -e $path2;

$t->post_ok('/do/add' => form => { account => 'one',
				   Test => 'on',
				   Test2 => 'on' })
    ->status_is(200)
    ->text_is('h1' => 'Add an account')
    ->content_like(qr'The account one was added to the following lists:\s+Test');

is($path->slurp(), "one\n", 'no duplicates saved');
ok(! -e $path2, "missing list was not created");

done_testing();
