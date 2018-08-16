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

$t->get_ok('/')
    ->status_is(200)
    ->text_is('title' => 'Trunk for Mastodon') # template
    ->text_is('h1' => 'Trunk for Mastodon');   # index.md

done_testing();
