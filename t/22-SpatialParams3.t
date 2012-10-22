#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;
use English qw{
    -no_match_vars
};

use rlib;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::SpatialParams;
use Biodiverse::TestHelpers qw{
    :basedata
    compare_arr_vals
};

use Data::Section::Simple qw{
    get_data_section
};

sub artifical_base_data {
    my %args = @_;

    my $res         = $args{res};         # [x, y] size of each cell
    my $bottom_left = $args{bottom_left}; # [x, y] bottom left corner
    my $top_right   = $args{top_right};   # [x, y] top right corner

    my $print_results = $args{print_results} || 0;

    my ($x_min, $x_max) = map { $_ / $res->[0] }
                              ($bottom_left->[0], $top_right->[0]);
    my ($y_min, $y_max) = map { $_ / $res->[1] }
                              ($bottom_left->[1], $top_right->[1]);

    return get_basedata_object (
        CELL_SIZES => $res,
        x_spacing  => $res->[0],
        y_spacing  => $res->[1],
        x_min      => $x_min,
        x_max      => $x_max,
        y_min      => $y_min,
        y_max      => $y_max,
        count      => 1,
    );
}

sub test_case {
    my %args = @_;

    my $bd            = $args{bd};       # basedata object
    my $cond          = $args{cond};     # spatial condition as string
    my $element       = $args{element};  # centre element
    my $count         = $args{count};    # amount of neighbours
    my $includes      = $args{includes}; # array of included cells as strings
    my $excludes      = $args{excludes}; # array of excluded cells as strings
    my $print_results = $args{print_results} || 0;

    my $spatial_params = Biodiverse::SpatialParams->new (
        conditions => $cond,
    );

    my $neighbours = eval {
        $bd->get_neighbours (
            element        => $element,
            spatial_params => $spatial_params,
        );
    };

    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($print_results) {
        use Data::Dumper;
        $Data::Dumper::Purity   = 1;
        $Data::Dumper::Terse    = 1;
        $Data::Dumper::Sortkeys = 1;

        my %gen_includes;
        my %gen_excludes;

        my @xdeltas = map { $_ * $bd->get_param('CELL_SIZES')->[0] } (-1..1);
        my @ydeltas = map { $_ * $bd->get_param('CELL_SIZES')->[1] } (-1..1);

        for my $neigh (keys %$neighbours) {
            # Check whether each of 9 adjacent cells are excluded.
            for my $dx (@xdeltas) { for my $dy (@ydeltas) {
                if ($dx == 0 && $dy == 0) {
                    next;
                }

                my $adj = transform_element (
                    element   => $neigh,
                    transform => [$dx, $dy, 1, 1]
                );

                if (!exists $neighbours->{$adj}) {
                    undef $gen_excludes{$adj};
                    undef $gen_includes{$neigh};
                }
            } }
        }

        print Dumper {
            count    => scalar keys $neighbours,
            includes => [sort keys %gen_includes],
            excludes => [sort keys %gen_excludes]
        };
    }

    ok $count == keys %$neighbours,
       'The correct amount of neighbours was returned';

    verify_set_contents (
        set      => $neighbours,
        includes => $includes,
        excludes => $excludes
    );
}

=item transform_element

Takes in a colon or comma (or any punctuation) separated pair of x and y values
(element) and scales them by the array ref of
[x_translate, y_translate, x_scale, y_scale] passed in as transform.

Returns colon separated pair of x and y.

=cut

sub transform_element {
    my %args = @_;

    my $element   = $args{element};
    my $transform = $args{transform};

    if (not ($element =~ m/^([-.0-9]+)([^-.0-9]+)([-.0-9]+)$/)) {
        croak "Invalid element '$element' given to transform_element.";
    }

    my ($x, $sep, $y)           = ($1, $2, $3);
    my ($x_t, $y_t, $x_s, $y_s) = @$transform;

    return join $sep, $x_s * ($x + $x_t),
                      $y_s * ($y + $y_t);
}

=item run_case_transformed

Takes in name of the test (name), the test data as a string (datastr) and a
transform as a 4 element array ref (transform).

The transform is in the order
[x_translate, y_translate, x_scale, y_scale]

It is applied to the base data coordinates, centre element, result elements
and numbers inside spatial conditions when prefixed by either XX or YY.

Translation is applied before scaling, and therefore should be specified in
terms of the original coordinates.

e.g.

sp_ellipse (major_radius => XX400000, minor_radius => YY200000)

=cut

my $re1 = join qr'\s+', ('([-0-9.,]+)',) x 3;

sub run_case_transformed {
    my %args = @_;

    my $k  = $args{name};
    my %v  = %{$args{data}};
    my $tf = $args{transform};

    my $res = [split ',', transform_element (
        element   => $v{res},
        transform => [0, 0, @$tf[2,3]], # Don't translate the resolution
    )];

    my ($bottom_left, $top_right) = map {[split ',', transform_element (
        element   => $_,
        transform => $tf
    )]} @v{'bottom_left', 'top_right'};

    my $bd = artifical_base_data (
        res           => $res,
        bottom_left   => $bottom_left,
        top_right     => $top_right,
    );

    my $element = transform_element (
        element   => $v{element},
        transform => $tf,
    );

    my %conds = %{$v{conds}};

    ok (%conds, "Test case $k actually contained conditions");

    while (my ($cond, $v1ref) = each %conds) {
        my %v1 = %$v1ref;

        $cond =~ s/XX/$tf->[2] * /g;
        $cond =~ s/YY/$tf->[3] * /g;

        my ($includes, $excludes) = map {[
            map { transform_element (
                element   => $_,
                transform => $tf,
            ) } @$_
        ]} @v1{'includes', 'excludes'};

        subtest "Passed condition $cond" => sub { test_case (
            bd            => $bd,
            element       => $element,
            cond          => $cond,
            count         => $v1{count},
            includes      => $includes,
            excludes      => $excludes,
            print_results => 1,
        ) };
    }
}

my $data = get_data_section;

my @transforms = (
    [0,0 , 1,1],               # id. [x_translate,y_translate , x_scale,y_scale]
    #[0,0 , .0000001,.0000001], # scaled to values < 1
    #[-200000,-200000 , 1,1],   # negative centre
);

for my $k (sort keys %$data) {
    for my $transform (@transforms) {
        run_case_transformed (
            name      => $k,
            data      => eval $data->{$k},
            transform => $transform,
        );
    }
}

done_testing;

1;

__DATA__

@@ CASE1
{
    'res'         => '100000,100000',
    'bottom_left' => '-500000,-500000',
    'top_right'   => '500000,500000',

    'element'     => '50000:50000',
    'conds'       => {
        'sp_circle (radius => XX0)' =>
{
  'count' => 1,
  'excludes' => [
                  '-50000:-50000',
                  '-50000:150000',
                  '-50000:50000',
                  '150000:-50000',
                  '150000:150000',
                  '150000:50000',
                  '50000:-50000',
                  '50000:150000'
                ],
  'includes' => [
                  '50000:50000'
                ]
},
        # TODO: more conditions
    },
}
