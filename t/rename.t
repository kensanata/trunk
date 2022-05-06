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

$t->get_ok('/rename')
    ->status_is(302)
    ->header_is('/login');

$t->ua->max_redirects(1);
$t->get_ok('/rename')
    ->status_is(200)
    ->text_is('h1' => 'Trunk Login')
    ->element_exists('form[action=/login]')
    ->element_exists('label[for=username]')
    ->element_exists('input[name=username][type=text]')
    ->element_exists('input[name=action][type=hidden][value=rename]');

$t->app->config({users=>{alex=>'let me in'}});

# make sure this list exists
$old_path = Mojo::File->new('Test.txt');
$old_path->spurt("") unless -e $old_path;
$old_desc = Mojo::File->new('Test.md');
$old_desc->spurt("") unless -e $old_desc;

$new_path = Mojo::File->new('Test2.txt');
unlink($new_path) if -e $new_path;
$new_desc = Mojo::File->new('Test2.md');
unlink($new_desc) if -e $new_desc;

$t->get_ok('/login' => form => {
  username => 'alex',
  password => 'let me in',
  action => 'rename'})
    ->status_is(200)
    ->text_is('h1' => 'Rename a list')
    ->element_exists('form[action=/do/rename]')
    ->element_exists('input[name=old_name][type=radio][value=Test]')
    ->element_exists('input[name=new_name][type=text]');

$t->post_ok('/do/rename' => form => { old_name => '' })
    ->status_is(500)
    ->text_is('h1' => 'Error')
    ->content_like(qr'Please pick a list to rename');

$t->post_ok('/do/rename' => form => { old_name => 'Test2' })
    ->status_is(500)
    ->text_is('h1' => 'Error')
    ->content_like(qr'This list does not exist');

$t->post_ok('/do/rename' => form => { old_name => 'Test' })
    ->status_is(500)
    ->text_is('h1' => 'Error')
    ->content_like(qr'Please provide a new list name');

$new_path->spurt("");

$t->post_ok('/do/rename' => form => { old_name => 'Test', new_name => 'Test2' })
    ->status_is(500)
    ->text_is('h1' => 'Error')
    ->content_like(qr'This list already exists');

unlink($new_path);

$t->post_ok('/do/rename' => form => { old_name => 'Test', new_name => 'Test2' })
    ->status_is(200)
    ->text_is('h1' => 'Rename a list')
    ->content_like(qr'The list <em>Test</em> was renamed to <em>Test2</em>');

ok(! -e $old_path, 'Test.txt is gone');
ok(-e $new_path, 'Test2.txt exists');
ok(! -e $old_desc, 'Test.md is gone');
ok(-e $new_desc, 'Test2.md exists');

done_testing();
