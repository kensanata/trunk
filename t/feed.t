#!/usr/bin/env perl

# Copyright (C) 2020 Alex Schroeder <alex@gnu.org>

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

my $t = Test::Mojo->new();

$reviews = Mojo::File->new('admin.log');
$reviews->spurt('[2020-08-04 11:26:34.58524] [26692] [info] alex added kensanata@octodon.social to Communes, Cooperatives, Digital Rights, Distributed Networks, Economics, Education, Ethics, FLOSS, Free Culture, Free Software, Functional Programming, Interaction Design, KDE, Libertarian, Linux, Politics, Privacy, Socialists, US Politics, World Politics');

$t->get_ok('/feed')
    ->status_is(200)
    ->text_is('channel title' => 'Trunk additions: all');

done_testing();
