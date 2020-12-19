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

$t->get_ok('/review')
    ->status_is(302)
    ->header_is('/login');

$t->ua->max_redirects(1);
$t->get_ok('/review')
    ->status_is(200)
    ->text_is('h1' => 'Login')
    ->element_exists('form[action=/login]')
    ->element_exists('label[for=username]')
    ->element_exists('input[name=username][type=text]')
    ->element_exists('input[name=action][type=hidden][value=review]');

$t->app->config({users=>{alex=>'let me in'}});

# make sure this list exists: three unique accounts
$path1 = Mojo::File->new('Test1.txt');
$path1->spurt('alex@example.org alex@example.com');
$path2 = Mojo::File->new('Test2.txt');
$path2->spurt('alex@example.org alex@example.net');

$reviews = Mojo::File->new('reviews');
$reviews->spurt('{ "alex@example.com": "reviewed 2019-12-15 by alex" }');

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'review'})
    ->status_is(200)
    ->text_is('h1' => 'Review accounts')
    ->element_exists('form[action=/do/review]')
    ->element_exists('input[name=account][value=alex@example.org][type=checkbox]')
    ->element_exists('input[name=account][value=alex@example.com][type=checkbox]')
    ->element_exists('input[name=account][value=alex@example.net][type=checkbox]')
    ->content_like(qr'reviewed 2019-12-15 by alex');

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    localtime(time);
my $today = sprintf("%02d-%02d-%04d", $mday, $mon + 1, $year + 1900);

$t->post_ok('/do/review' => form => { account => 'alex@example.org' })
    ->status_is(200)
    ->text_is('h1' => 'Review accounts')
    ->content_like(qr'One account was marked as reviewed');

my $data = $reviews->slurp();
unlike($data, qr/null/, "no nulls in the review file");

done_testing();
