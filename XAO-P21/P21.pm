package XAO::P21;
use strict;
use IO::Socket::INET;
use XAO::Errors qw(XAO::P21);
use XAO::Utils;

##
# Package version
#
use vars qw($VERSION);
$VERSION = '0.10';

###############################################################################

=head1 NAME

XAO::P21 - Perl extension for network interaction with prophet21.

=head1 SYNOPSIS

  use XAO::P21;

=head1 DESCRIPTION

This module is intended for remote interaction with prophet21 system; it is mainly client-side stub for web server.

=head1 METHODS

=over

=cut

###############################################################################

=item new

The constructor. Usage:

    my $client = XAO::P21->new( PeerPort => 9009 );

The server assumed at localhost; if real server is located at some remote site,
then secure tunnel should help.    

=cut

sub new {
    my ($proto, %param) = @_;
    my $self = { Proto => 'tcp', PeerAddr => '127.0.0.1', PeerPort => 9009 };
    foreach (keys %param) {
        $self->{$_} = $param{$_};
    }
    bless $self, $proto;
}

sub connect {
    my $self = shift;
    $self->{Socket} = IO::Socket::INET->new(%$self);
    throw XAO::E::P21 "connect - $!" unless $self->{Socket};
}

###############################################################################

=item call ($build, $callback, @params)

(Private method)

Sends untranslated list of parameters to the server and receives
results. Results are given to `build' subroutine and then to
`callback'. Usually `build' would split individual fields to an array or
hash, and `callback' would print or somehow use these values.

Default callback is to create an array of all resulting rows and then
return a reference to this array.

Build does not have a default and must be provided.

=cut

sub call {
    my ($self, $build, $callback, @params) = @_ ;

    my $list;
    if(!$callback) {
        $list=[];
        $callback = sub { push @$list, $_[0]; $list };
    }

    $self->connect unless $self->{Socket};
    my $socket=$self->{Socket};

    my $flag=0;
    local $SIG{PIPE} = sub { $flag = 1 };
    print $socket join("\t", map { defined($_) ? $_ : '' } @params), "\n";
    unless ($flag) {
        my $result;
        while(<$socket>) {
            chomp;
            return $result if /^\.$/;
            $result = $callback->($build->($_));
        }
        delete $self->{Socket};
        throw XAO::E::P21 "call - unexpected eof reading from socket";
    }

    delete $self->{Socket};
    throw XAO::E::P21 "call - SIGPIPE writing to socket";
}

###############################################################################

=item items

Returns full items list from "item" table; each line contains: item code,
package size, sales unit, sku, list price, alternate unit name or "?",
alternate unit size or "?", description string 1, description string 2, upc.
All the fields in line delimited with "\t".

One optional parameter is a reference to callback procedure, which accepts one
parameter - reference to item object. If it is missing, then the method returns
reference to list of item object references.

=cut  

sub items {
    my ($self, $callback, $table) = @_;
    $self->call( sub {
        my ($item_code, $prod_group, $pkg_size, $sales_unit,
            $sku, $list_price, $alt_ut_name, $alt_ut_size,
            $desc1, $desc2, $upc, $cat_page) = split /\t/, $_[0];
        {
            item_code   => $item_code,
            prod_group  => $prod_group,
            pkg_size    => $pkg_size,
            sales_unit  => $sales_unit,
            sku         => $sku,
            list_price  => $list_price,
            alt_ut_name => $alt_ut_name,
            alt_ut_size => $alt_ut_size,
            desc1       => $desc1,
            desc2       => $desc2,
            upc         => $upc,
            cat_page    => $cat_page,
        }
    }, $callback, $table || 'items');
}

###############################################################################

=item avail

Returns availability info for each of given item code. The info contains
lines with non-zero quantities only.

Synopsis:

XAO::P21->new->avail( customer => 'CUST_CODE',
                      callback => sub { print $_[0], "\n" },
                      item => '021200-82221' );

or

XAO::P21->new->avail( item => [ '021200-82221', '021200-082222' ] );

=cut  

sub avail {
    my ($self, %param) = @_;
    my $item=$param{item};
    $self->call( sub {
        my ($code, $location, $stlev, $junk1, $unit,
            $description, $junk2, $locn) = split /\t/, $_[0];
        {
            code        => $code,
            location    => $location,
            stock_level => $stlev,
            unit        => $unit,
            description => $description,
            descript2   => $junk2,
            location_code => $locn,
        }
        }, $param{callback}, 'avail', $param{customer} || '?',
        ref($item) eq 'ARRAY' ? @$item : $item);
}

###############################################################################

=item catalog

Returns full catalog items list. By default, if no 'callback' function
is provided it will return a reference to an array of hash references:

 item_code      => item code
 prod_group     => category
 sales_group    => sales schedule referencing sell_schd table
 vend_number    => secondary key for sales schedule matching
 pkg_size       => package size
 sales_unit     => sales unit
 sku            => stock keeping unit
 desc1          => description line 1
 desc2          => description line 2
 upc            => UPC
 cat_page       => product flags
 list_price     => list price
 col1_price     => column 1 price
 col2_price     => column 1 price
 col3_price     => column 1 price
 alt_units      => array of alternative units if any, each
                   one in NAME/SIZE format

=cut  

sub catalog {
    my ($self, $callback) = @_;
    $self->call( sub {
        my ($item_code, $prod_group, $sales_group, $vend_number,
            $pkg_size, $sales_unit,
            $sku, $desc1, $desc2, $upc, $cat_page,
            $list_price, $col1_price, $col2_price, $col3_price,
            @alt_units) = split /\t/, $_[0];
        return {
            item_code   => $item_code,
            prod_group  => $prod_group,
            sales_group => $sales_group,
            vend_number => $vend_number,
            pkg_size    => $pkg_size,
            sales_unit  => $sales_unit,
            sku         => $sku,
            desc1       => $desc1,
            desc2       => $desc2,
            upc         => $upc,
            cat_page    => $cat_page,
            list_price  => $list_price,
            col1_price  => $col1_price,
            col2_price  => $col2_price,
            col3_price  => $col3_price,
            alt_units   => \@alt_units,
        };
    }, $callback, 'catalog');
}

###############################################################################

=item cust_item

Returns custom priced items in an array of hashes:

  cust_code     => 
  item_code     => 
  sales_price   => 

=cut  

sub cust_item {
    my $self=shift;
    my $args=get_args(\@_);

    my $callback=$args->{callback};

    my $build=$args->{build} || sub {
        my %row;
        @row{qw(cust_code item_code sales_price)}=split('\t',$_[0]);
        return \%row;
    };

    $self->call($build,$callback,'cust_item');
}

###############################################################################

=item sell_schd

Returns sell_schd dump:

  disc_group                => code referenced by 'sales_group'
  vend_number               => vendor number from catalog or '' for default
  disc_basis_disp           => PIECE or COL1
  disc_code_disp            => COL1 or LIST or PRICE
  disc_type_disp            => MULT
  break_1 .. break_8        => break levels
  discount_1 .. discount_8  => break values

=cut  

sub sell_schd {
    my $self=shift;
    my $args=get_args(\@_);

    my $callback=$args->{callback};

    my $build=$args->{build} || sub {
        my ($group,$vendor,$basis,$code,$type,$breaks,$discounts)=split('\t',$_[0]);
        my @b=split(/\//,$breaks);
        my @d=split(/\//,$discounts);
        my %row=(
            disc_group      => $group,
            vend_number     => $vendor,
            disc_basis_disp => $basis,
            disc_code_disp  => $code,
            disc_type_disp  => $type,
        );
        for(my $i=1; $i<=8; $i++) {
            $row{"break_$i"}=$b[$i-1] || 0;
            $row{"discount_$i"}=$d[$i-1] || 0;
        }
        return \%row;
    };

    $self->call($build,$callback,'sell_schd');
}

###############################################################################

=item custinfo

Returns list with info about customers. Each entry in the list is a
hash:

  cust_code     => 
  bill_to_name  => 
  bill_to_addr1 => 
  bill_to_addr2 => 
  bill_to_addr3 => 
  bill_to_city  => 
  bill_to_state => 
  bill_to_zip   => 
  telephone     => 
  aux_fax       => 
  email_address => 
  slm_number    => territory/salesman number
  first_sale    => date of first sale
  stax_exemp    => if non-empty then this customer has tax exempt
                   documents on file

Default is to return complete list of all customers, be careful as it
can take a lot of time to do so.

Synopsis:

 my $rlist=$client->custinfo;

 $client->custinfo(callback => \&some_callback,
                   code     => ['21CASH, 'PI10MP']);

 my $rlist = $client->custinfo(code => '21CASH');

=cut  

sub custinfo {
    my $self=shift;
    my $args=get_args(\@_);

    my $custinfo=$args->{code} || [];
    $custinfo=[ $custinfo ] unless ref($custinfo) eq 'ARRAY'; 

    my $callback=$args->{callback};

    my $build=$args->{build} || sub {
        my %row;
        @row{qw(bill_to_name cust_code bill_to_addr1 bill_to_addr2
                bill_to_addr3 bill_to_city bill_to_state bill_to_zip
                telephone aux_fax email_address slm_number first_sale
                stax_exemp)}=
            split('\t',$_[0]);
        return \%row;
    };

    $self->call($build,$callback,'custinfo',@$custinfo);
}

###############################################################################

=item modcust

Modifies customer data, according to custinfo.

=cut

sub modcust {
    my $self=shift;
    my $args=get_args(\@_);
    print STDERR join(' ',(
                     $args->{cust_code},
                     $args->{bill_to_name},
                     $args->{bill_to_addr1},
                     $args->{bill_to_addr2},
                     $args->{bill_to_addr3},
                     $args->{bill_to_city},
                     $args->{bill_to_state},
                     $args->{bill_to_zip},
                     $args->{telephone},
                     $args->{aux_fax},
                     $args->{email_address},
                     $args->{slm_number},
                     $args->{first_sale},
                          ), "\n");
    $self->call(sub { $_[0] }, undef, 'mod_custinfo',
                     $args->{cust_code},
                     $args->{bill_to_name},
                     $args->{bill_to_addr1},
                     $args->{bill_to_addr2},
                     $args->{bill_to_addr3},
                     $args->{bill_to_city},
                     $args->{bill_to_state},
                     $args->{bill_to_zip},
                     $args->{telephone},
                     $args->{aux_fax},
                     $args->{email_address},
                     $args->{slm_number},
                     $args->{first_sale});
}

###############################################################################

=item order

Places order into spool. The only argument is ref to list of ref to hashes.
The hash contains following attributes:

 reference_number => a unique string which is used to name the temporary
                     order file in the P21 ecommerce spool folder.
 customer         => the Prophet 21 unique customer code.
 date             => formatted Year Month Day without any delimiters,
                     e.g. 020206
 po               => the customer's purchase order number
 credit_card      => the customer's credit card number if applicable
 card_exp_month   => customer's cc expiry month
 card_exp_year    => customer's cc expiry year
 name             => the customer's dba name
 address1         => the first ship-to address line
 address2         => the second ship-to address line
 city             => the customer's ship-to city
 state            => the customer's ship-to state
 zip              => the customer's ship-to zip
 inst1            => a short instruction field of 30 characters
 inst2            => the second short instruction field of 30 chars
 line_number      => the row number for this entry, first row being 1 (one)
 qty              => quantity ordered for this item
 itemcode         => a valid P21 itemcode (not a customer itemcode!)
 price            => base unit price (unit_price/unit_size)
 unit_name        => unit name
 unit_size        => unit size
 email            => email address for further notification
 stax_exemp       => order line sales tax exemption status
 suspended_order  => boolean for the initial state of the order
                     once injected into p21

Returns a hash reference with 'result' and 'info' members. Where
result is zero for success and info contains internally used
order ID which is the same as provided currenly.

=cut  

sub order {
    my $self=shift;
    my $order_list=shift;

    my $constr=sub {
        my ($result, $info) = split /\t/, $_[0];
        return { result => $result, info => $info };
    };

    my $callback=sub {
        $_[0];
    };

    my @order_array=map {
        $_->{reference_number},             #  1 |  1
        $_->{customer},                     #  2 |  2
        $_->{date},                         #  3 |  3
        $_->{po},                           #  4 |  4
        $_->{credit_card},                  #  5 |  5
        $_->{card_exp_month},               #  6 |  6
        $_->{card_exp_year},                #  7 |  7
        $_->{name},                         #  8 |  8
        $_->{address1},                     #  9 |  9
        $_->{address2},                     # 10 | 10
        $_->{city},                         # 11 | 11
        $_->{state},                        # 12 | 12
        $_->{zip},                          #  1 | 13
        $_->{inst1},                        #  2 | 14
        $_->{inst2},                        #  3 | 15
        $_->{line_number},                  #  4 | 16
        $_->{itemcode},                     #  5 | 17
        $_->{qty},                          #  6 | 18
        $_->{price},                        #  7 | 19
        $_->{email},                        #  8 | 20
        '',                                 #  9 | 21
        '',                                 # 10 | 22
        '',                                 # 11 | 23
        '',                                 # 12 | 24
        '',                                 #  1 | 25
        '',                                 #  2 | 26
        '',                                 #  3 | 27
        $_->{stax_exemp},                   #  4 | 28
        $_->{stax_exemp} ? 'N' : 'Y',       #  5 | 29
        $_->{suspended_order} ? 'Y' : 'N',  #  6 | 30
        $_->{unit_name} || '',              #  7 | 31
        $_->{unit_size} || 1,               #  8 | 32
        $_->{account_number} || '',         #  9 | 33
    } @$order_list;

    $self->call($constr,$callback, 'order_entry', @order_array);
}

###############################################################################

=item price

Asks for price. Input data is: customer code ("?" is allowed), item_code,
quantity. Returns reference to a hash:

 price      => price per unit
 mult       => multiplier
 total      => price * mult * quantity

Net price is (price per unit) * multiplier.

=cut  

sub price {
    my $self=shift;
    my $args=get_args(\@_);

    my $quantity = $args->{quantity} || 1;
    my $customer = $args->{customer};
    my $itemcode = $args->{itemcode} || $args->{item};

    $self->call(sub {
                    my ($price, $mult) = split /\t/, $_[0];
                    $price=0 if $price eq '?';
                    return {
                        price   => $price,
                        mult    => $mult,
                        total   => $price * $mult * $quantity,
                    };
                },
                sub {
                    return $_[0];
                },
                'price',
                $customer,
                $itemcode,
                $quantity);
}

###############################################################################

=item view_order_details

Returns full information about the given order. Example:

    my $res=$cl->view_order_details(order_id => 1234567);

Returns array of hash references with order line infos.

Another example:

    my $res=$cl->view_order_details(order_id => 1234567,
                                    callback => \&print_each_line);

=cut

sub view_order_details {
    my $self=shift;
    my $args=get_args(\@_);

    my $order_id=$args->{order_id} ||
        throw XAO::E::P21 "view_order_details - no 'order_id' given";

    my $build=sub {
        my $str=shift;
        my @arr=split(/\t/,$str);

        my %line;
        if($arr[0] eq 'LINE') {
            @arr==10 ||
                throw XAO::E::P21 "view_order_details - wrong LINE ($str)";
            @line{qw(type item_code entry_date
                     ord_qty inv_qty canc_qty
                     ut_price ut_size
                     disposition disposition_desc)}=@arr;
        }
        elsif($arr[0] eq 'INVOICE') {
            @arr==8 ||
                throw XAO::E::P21 "view_order_details - wrong INVOICE ($str)";
            @line{qw(type ship_number ord_date inv_date ship_date
                     total_stax_amt out_freight cust_code)}=@arr;
        }
        elsif($arr[0] eq 'ITEM') {
            @arr==4 ||
                throw XAO::E::P21 "view_order_details - wrong ITEM ($str)";
            @line{qw(type ship_number item_code inv_qty)}=@arr;
        }
        else {
            throw XAO::E::P21 "view_order_details - unknown type=$arr[0] ($str)";
        }

        return \%line;
    };

    $self->call($build,
                $args->{callback},
                'view_order_details',
                $order_id);
}

###############################################################################

=item match

Finds matches of order numbers for reference numbers.  Returns hash with keys:
refnum (customer reference number), file (OS filename), order (P21 order
number).

=cut

sub find_match {
    my $self = shift;
    my $args = get_args(\@_);
    $self->call( sub {  my ($refnum, $file, $order) = split /\t/, $_[0];
                        { refnum => $refnum, file => $file, order => $order } },
                 $args->{callback}, 'find_match', @{$args->{refs}} );
}

###############################################################################

=item show_spool

Shows contents of order spool directory, one filename per line.

=cut

sub show_spool {
    my ($self, $callback) = @_;
    $self->call(sub { $_[0] }, $callback, 'show_spool');
}

###############################################################################

=item cleanup_spool

Removes one or more files from order spool directory.

Synopsis:

$client->cleanup_spool(file=>['file1', 'file2']);

=cut

sub cleanup_spool {
    my $self = shift;
    my $args = get_args(\@_);
    $self->call(sub { 0 }, undef, 'cleanup_spool', @{$args->{file}} );
}

###############################################################################
1;
__END__

=back

=head1 BUGS

The documentation is too incomplete. Remote exceptions are unhandled.

=head1 AUTHORS

Copyright (c) 2001-2002 XAO Inc.

E.Karpachov <jk@xao.com>, Andrew Maltsev <am@xao.com>

=head1 SEE ALSO

perl(1), P21_Acclaim(3), XAO::Errors(3)
