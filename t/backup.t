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
use Mojo::File;

require './trunk.pl';

unlink <Test.txt*>;

foreach (qw(Test.txt Test.txt.~4~ Test.txt.~14~)) {
  my $path = Mojo::File->new($_);
  $path->spurt($_);
}

my $path = Mojo::File->new("Test.txt");
backup($path) if -e $path;

ok(-e 'Test.txt.~15~', "new backup created");

is(Mojo::File->new("Test.txt.~15~")->slurp(), "Test.txt", "backup content correct");

done_testing();
