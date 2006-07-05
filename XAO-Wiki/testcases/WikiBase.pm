package testcases::WikiBase;
use strict;
use XAO::Utils;
use XAO::Objects;
use Data::Dumper;

use base qw(XAO::testcases::Web::base);

### sub test_interface {
###     my $self=shift;
### 
###     my $wiki=XAO::Objects->new(objname => 'Wiki::Base');
###     $self->assert($wiki && ref $wiki,
###                   "Can't get Wiki::Base object");
### 
###     my @public_methods=qw(
###         data_structure
###         build_structure
###         parse
###         store
###         retrieve
###         render_html
###     );
### 
###     foreach my $method (@public_methods) {
###         dprint $method;
###         my $mcode=$wiki->can($method);
###         $self->assert($mcode && ref($mcode) eq 'CODE',
###                       "Expected Wiki::Base to have '$method' method");
###     }
### }

###############################################################################

sub test_storage {
    my $self=shift;

    my $wiki=XAO::Objects->new(objname => 'Wiki::Base');
    $self->assert($wiki && ref $wiki,
                  "Can't get Wiki::Base object");

    my %ds=$wiki->data_structure;
    $self->assert(scalar(%ds),
                  "Wiki::Base::data_structure failed");
    $self->assert($ds{'Wiki'} && $ds{'Wiki'}->{'class'} eq 'Data::Wiki',
                  "Expected to have /Wiki in the structure definition");
    $self->assert($ds{'Wiki'}->{'structure'}->{'Revisions'} && $ds{'Wiki'}->{'structure'}->{'Revisions'}->{'class'} eq 'Data::WikiRevision',
                  "Expected to have /Wiki/Revisions in the structure definition");
                
    $wiki->build_structure;

    my $odb=$self->siteconfig->odb;
    $self->assert($odb->fetch('/')->exists('Wiki'),
                  "No /Wiki in the database after build_structure");

    my $content=<<EOT;
= Header Text =
Some text with a [[link]].
EOT

    $odb->transact_begin;
    my $now=time;
    my $member_id='foo';
    my $wiki_id=$wiki->store(
        content         => $content,
        edit_member_id  => $member_id,
        edit_time       => $now,
    );
    $odb->transact_commit if $odb->transact_active;
    $self->assert($wiki_id,
                  "Failed to store new wiki content");

    my $wiki_list=$odb->fetch('/Wiki');
    $self->assert($wiki_list->exists($wiki_id),
                  "No record in the database after successsful store ($wiki_id)");

    my ($db_content,$db_edit_time,$db_member_id)=$wiki->retrieve(
        wiki_id     => $wiki_id,
        fields      => [ qw(content edit_time edit_member_id) ],
    );
    $self->assert($db_content,
                  "Got no content from the database (wiki_id=$wiki_id)");
    $self->assert($db_content eq $content,
                  "Content in the database differs from stored");
    $self->assert($db_edit_time,
                  "Got no edit_time from the database (wiki_id=$wiki_id)");
    $self->assert($db_edit_time eq $now,
                  "Edit_time in the database ($db_edit_time) differs from stored ($now)");
    $self->assert($db_member_id,
                  "Got no edit_member_id from the database (wiki_id=$wiki_id)");
    $self->assert($db_edit_time eq $now,
                  "Edit_member_id in the database ($db_member_id) differs from stored ($member_id)");
}

### ###############################################################################
### 
### sub test_parse {
###     my $self=shift;
### 
###     my $wiki=XAO::Objects->new(objname => 'Wiki::Foo');
###     $self->assert($wiki->isa('XAO::DO::Wiki::Base'),
###                   "Expected Wiki::Foo to be based on Wiki::Base");
### 
###     my %tests=(
###         t001        => {
###             template    => "blah\n==some header==\nafter",
###             expect      => [
###                 {   type        => 'header',
###                     content     => 'some header',
###                 },
###             ],
###         },
###         t002        => {
###             template    => "blah\n==  some header  ==\nafter",
###             expect      => [
###                 {   type        => 'header',
###                     content     => 'some header',
###                 },
###             ],
###         },
###         t003        => {
###             template    => "blah\n===some header==\nafter",
###             expect_not  => [
###                 {   type        => 'header',
###                     content     => 'some header',
###                 },
###             ],
###         },
###         #
###         # Strange, but this is how Wikipedia parses it, so keeping ourselves compatible
###         #
###         t004        => {
###             template    => "blah\n==some header== xxx\nafter",
###             expect      => [
###                 {   type        => 'header',
###                     content     => 'some header',
###                 },
###             ],
###         },
###         t010        => {
###             template    => "blah\n===    some   subheader===  \nafter",
###             expect      => [
###                 {   type        => 'header',
###                     level       => 3,
###                     content     => 'some   subheader',
###                 },
###             ],
###         },
###         t011        => {
###             template    => "blah\nxxx ===    some   subheader===  \nafter",
###             expect_not      => [
###                 {   type        => 'subheader',
###                     content     => 'some   subheader',
###                 },
###             ],
###         },
###         t012        => {
###             template    => "\x{263a}",
###             expect      => [
###                 {   type        => 'text',
###                     content     => "<p>\x{263a}\n</p>\n",
###                 },
###             ],
###         },
###         t013        => {
###             template    => "Bold smiley -- '''\x{263a}'''",
###             expect      => [
###                 {   type        => 'text',
###                     content     => "<p>Bold smiley -- <b>\x{263a}</b>\n</p>\n",
###                 },
###             ],
###         },
###         t020        => {
###             template    => '{{}}',
###             expect_not  => [
###                 {   type        => 'curly',
###                 },
###             ],
###         },
###         t021        => {
###             template    => '{{fubar}}',
###             expect      => [
###                 {   type        => 'curly',
###                     opcode      => 'fubar',
###                     content     => '',
###                 },
###             ],
###         },
###         t022        => {
###             template    => "{{\n values\n| some=thing\n| other=that\n}}",
###             expect      => [
###                 {   type        => 'curly',
###                     opcode      => 'values',
###                     content     => '| some=thing | other=that',
###                 },
###             ],
###         },
###         #
###         t030        => {
###             template    => "blah {{fubar}} blah",
###             expect      => [
###                 {   type        => 'fubar',
###                     content     => '',
###                 },
###             ],
###         },
###     );
### 
###     $self->run_parse_tests($wiki,\%tests);
### }
### 
### ###############################################################################
### 
### sub run_parse_tests ($$$) {
###     my ($self,$wiki,$tests)=@_;
### 
###     eval 'use Data::Compare';
###     if($@) {
###         print STDERR "\n" .
###                      "Perl extension Data::Compare is not available, skipping tests\n" .
###         return;
###     }
### 
###     ##
###     # For each test checking that we get _at least_ the blocks listed in
###     # 'expect' in the same order. There may be other blocks in parser
###     # response too.
###     #
###     foreach my $tid (sort keys %$tests) {
###         my $tdata=$tests->{$tid};
### 
###         my $rc=$wiki->parse(
###             content     => $tdata->{'template'},
###         );
###         $self->assert(!$rc->{'error'},
###                       "Got a parsing error ($rc->{'errstr'}) for test $tid");
###         $self->assert(!$rc->{'errstr'},
###                       "Got no error, but an unexpected error message ($rc->{'errstr'}) for test $tid");
### 
###         my $got=$rc->{'data'};
### 
###         my $got_pos=0;
###         my $expect=$tdata->{'expect'} || [ ];
###         for(my $i=0; $i<@$expect; ++$i) {
###             my $eblock=$expect->[$i];
###             my $found;
###             for(my $j=$got_pos; $j<@$got; ++$j) {
###                 $found=1;
###                 foreach my $k (keys %$eblock) {
###                     if(!defined $got->[$j]->{$k} || $got->[$j]->{$k} ne $eblock->{$k}) {
###                         $found=0;
###                         last;
###                     }
###                 }
###                 if($found) {
###                     $got_pos=$j;
###                     last;
###                 }
###             }
###             if(!$found) {
###                 print STDERR Dumper($got);
###                 $self->assert($found,
###                               "Can't find expected block (#=$i, type='$eblock->{'type'}', content='$eblock->{'content'}') for test $tid");
###             }
###         }
### 
###         my $exnot=$tdata->{'expect_not'} || [ ];
###         for(my $i=0; $i<@$exnot; ++$i) {
###             my $eblock=$exnot->[$i];
###             my $found;
###             for(my $j=0; $j<@$got; ++$j) {
###                 $found=1;
###                 foreach my $k (keys %$eblock) {
###                     if(!defined $got->[$j]->{$k} || $got->[$j]->{$k} ne $eblock->{$k}) {
###                         $found=0;
###                         last;
###                     }
###                 }
###                 if($found) {
###                     print STDERR Dumper($got);
###                     $self->assert(!$found,
###                                   "Found unexpected block (#=$i, type='$eblock->{'type'}', content='$eblock->{'content'}') for test $tid");
###                 }
###             }
###         }
###     }
### }

###############################################################################
1;