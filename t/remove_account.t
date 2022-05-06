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

# create list with one account
$path = Mojo::File->new('Test.txt');
$path->spurt("one\n");

my $t = Test::Mojo->new;

$t->get_ok('/remove')
    ->status_is(302)
    ->header_is('/login');

$t->ua->max_redirects(1);
$t->get_ok('/remove')
    ->status_is(200)
    ->text_is('h1' => 'Trunk Login')
    ->element_exists('form[action=/login]')
    ->element_exists('label[for=username]')
    ->element_exists('input[name=username][type=text]')
    ->element_exists('input[name=action][type=hidden][value=remove]');

$t->app->config({users=>{alex=>'let me in'}});

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'remove'})
    ->status_is(200)
    ->text_is('h1' => 'Remove an account')
    ->element_exists('form[action=/do/remove]')
    ->element_exists('label[for=account]')
    ->element_exists('input[name=account][type=text]');

$t->post_ok('/do/remove' => form => { account => 'one' })
    ->status_is(200)
    ->text_is('h1' => 'Remove an account')
    ->content_like(qr'The account one was removed from the following lists:\s+Test');

is($path->slurp(), "", 'account removed');

$path2 = Mojo::File->new('Test2.txt');
unlink($path2) if -e $path2;

$t->post_ok('/do/remove' => form => { account => 'one' })
    ->status_is(200)
    ->text_is('h1' => 'Account not found')
    ->content_like(qr'The account one was not found on any list');

ok(! -e $path2, "missing list was not created");

done_testing();
