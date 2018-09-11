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
use Mojo::JSON qw(decode_json);

require './trunk.pl';

# create empty queue
$path = Mojo::File->new('queue');
unlink($path) if -e $path;

my $t = Test::Mojo->new;

$t->app->config({users=>{alex=>'let me in'}});

$t->get_ok('/api/v1/queue')
    ->status_is(200)
    ->json_is('' => []);

$t->post_ok('/api/v1/queue' => form => {})
    ->status_is(500)
    ->text_like('p' => qr'Must be authenticated');

$t->post_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in'})
    ->status_is(500)
    ->text_like('p' => qr'Missing acct parameter');

$t->post_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in',
  acct => 'kensanata@octodon.social'})
    ->status_is(500)
    ->text_like('p' => qr'Missing name parameter');

$t->post_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in',
  name => 'BSD'})
    ->status_is(500)
    ->text_like('p' => qr'Missing acct parameter');

$t->post_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in',
  acct => 'kensanata@octodon.social'})
    ->status_is(500)
    ->text_like('p' => qr'Missing name parameter');

$t->post_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in',
  acct => 'kensanata@octodon.social',
  name => 'BSD'})
    ->status_is(200);

ok(-e $path, "queue exists");
my $data = decode_json $path->slurp();
is(@$data, 1, 'enqueued one item');
is($data->[0]->{acct}, 'kensanata@octodon.social', 'acct saved');
is($data->[0]->{names}->[0], 'BSD', 'list name saved');

$t->get_ok('/queue')
    ->status_is(200)
    ->text_like('form p a' => qr'kensanata@octodon\.social')
    ->text_is('form p label' => 'BSD');

$t->delete_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in',
  acct => 'kensanata@octodon.social'})
    ->status_is(200);

$t->delete_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in',
  acct => 'kensanata@octodon.social'})
    ->status_is(404);

$data = decode_json $path->slurp();
is(@$data, 0, 'queue is empty');

$t->post_ok('/api/v1/queue' => form => {
  username => 'alex',
  password => 'let me in',
  acct => 'kensanata@octodon.social',
  name => 'BSD'})
    ->status_is(200);

$t->get_ok('/queue/delete' => form => {
  username => 'alex',
  password => 'let me in',
  acct => 'kensanata@octodon.social'})
    ->status_is(200)
    ->text_is('p' => 'The account kensanata@octodon.social was deleted from the queue.');

$data = decode_json $path->slurp();
is(@$data, 0, 'queue is empty');

done_testing();
