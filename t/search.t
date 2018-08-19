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

use Test::Mojo;
use Test::More;

require './trunk.pl';

my $t = Test::Mojo->new();

$t->get_ok('/search')
    ->status_is(302)
    ->header_is('/login');

$t->ua->max_redirects(1);
$t->get_ok('/search')
    ->status_is(200)
    ->text_is('h1' => 'Login')
    ->element_exists('form[action=/login]')
    ->element_exists('label[for=username]')
    ->element_exists('input[name=username][type=text]')
    ->element_exists('input[name=action][type=hidden][value=search]');

$t->app->config({users=>{alex=>'let me in'}});

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'search'})
    ->status_is(200)
    ->text_is('h1' => 'Search for an account')
    ->element_exists('form[action=/do/search]')
    ->element_exists('label[for=account]')
    ->element_exists('input[name=account][type=text]');

$path = Mojo::File->new('Test.txt');
$path->spurt("Alex");

$t->post_ok('/do/search' => form => { account => 'al' })
    ->status_is(200)
    ->text_is('h1' => 'Search for an account')
    ->element_exists('li a[href=/remove?account=Alex]');

done_testing();
