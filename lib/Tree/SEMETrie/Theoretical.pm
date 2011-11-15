package Tree::SEMETrie::Edge;

sub match { }

package Tree::SEMETrie::MultiEdge;

sub new {
	my $class = shift;
	$class = ref($class) || $class;
	my $self = {@_};
	bless $self, $class;
}

sub addEdge {	shift->{substr($_[0], 0, 1)} = $_[1] }
sub removeEdge { delete shift->{substr($_[0], 0, 1)} }

sub names { keys %{$_[0]} }
sub nodes { values %{$_[0]} }

sub match {
	my $self = shift;
	my ($key) = @_;

	return (
		substr($key, 1),
		$self->{substr($key, 0, 1)}
	);
}

package Tree::SEMETrie::SingleEdge;

sub new {
	my $class = shift;
	$class = ref($class) || $class;
	my $self = [shift(@_), shift(@_)];
	bless $self, $class;
}

sub names {
	my $self = shift;
	if (@_) { $self->[0] = shift @_ }
	return $self->[0];
}
sub nodes {
	my $self = shift;
	if (@_) { $self->[1] = shift @_ }
	return $self->[1];
}

sub match {
	my $self = shift;
	my ($key) = @_;
	
	my $max_match_length = List::Util::min(length($self->names), length($key));
	my $char_mismatch = 0;
	for (; $char_mismatch < $max_match_length; ++$char_iter) {
		last if substr($self->name, $char_mismatch, 1) ne substr($key, $char_mismatch, 1);
	}

	return (
		substr($self->names, 0, $char_mismatch),
		substr($self->names, $char_mismatch),
		substr($key, $char_mismatch),
		$char_mismatch == $max_match_length ? $self->nodes : undef
	);
}

package Tree::SEMETrie;

use strict;
use warnings;
use List::Util ();

use Tree::SEMETrie::Iterator;

#Class Constants
my $VALUE  = 0;
my $CHILDS = 1;
my $SINGLE_CHILD_KEY = 0;
my $SINGLE_CHILD_NODE = 1;

#Private Helper Functions

my $make_new_trie_ref = sub {
	return bless $_[0], ref($_[1]);
};

my $find_match_length_ref = sub {
	my $max_match_length = List::Util::min(length($_[0]), length($_[1]));
	my $char_iter = 0;
	for (; $char_iter < $max_match_length; ++$char_iter) {
		last if substr($_[0], $char_iter, 1) ne substr($_[1], $char_iter, 1);
	}
	return $char_iter;
};

my $split_string_at_position_ref = sub {
	return (
		substr($_[0], 0, $_[1]),
		substr($_[0], $_[1], 1),
		substr($_[0], $_[1] + 1),
	);
};

#compression algorithm :
# if node->value is null and node is only child
#   node->value = child->value
#   parent->key += child->key
#   parent->childs = node->childs
my $compress_trie_ref = sub {
	my ($node, $parent) = @_;

	#The node must not have a value and have no siblings
	return if $node->[$VALUE] || ref($parent->[$CHILDS]) ne 'ARRAY';

	$parent->[$CHILDS][$SINGLE_CHILD_KEY] .= $node->[$CHILDS][$SINGLE_CHILD_KEY];
	$parent->[$CHILDS][$SINGLE_CHILD_NODE] = $node->[$CHILDS][$SINGLE_CHILD_NODE];

	return;

};

my $merge_choice_ref = sub { $_[0] };

#Constructor

sub new {
	my $class = shift;
	$class = ref $class || $class;
	return bless [], $class;
}

#Root Accessors/Mutators

#Get a list of all immediate [path, child node] pairs
sub childs {
	my $self = shift;
	return $self->edges ? $self->edges->nodes : ();
}
*children = \&childs;

#Get/Set the value of the root
sub value {
	my $self = shift;
	if (@_) {
		${$self->[$VALUE]} = $_[0];
	}
	return $self->[$VALUE] ? ${$self->[$VALUE]} : undef;
}

#Validators

#Returns true if the root has any child paths
sub has_childs { ref($_[0][$CHILDS]) ne '' }
*has_children = \&has_childs;

#Returns true if the root has an associated value
sub has_value { defined $_[0][$VALUE] }

#Trie Accessors

#Gets every path to every stored value as [path, value] pairs
sub all {
	my $self = shift;

	my @results;
	for (my $iterator = $self->iterator; ! $iterator->is_done; $iterator->next) {
		push @results, [$iterator->key, $iterator->value];
	}

	return @results;
}

#Finds the root of a trie that matches the given key.  If no such subtrie exists, returns undef.
sub find {
	my $self = shift;
	my ($key) = @_;

	my $node = $self;

	my ($key_iter, $key_length) = (0, length $key);
	while ($key_iter < $key_length) {
		my $childs_type = ref($node->[$CHILDS]);

		#Key does not exist since we're at the end of the trie
		if (! $childs_type) { $node = undef; last }

		#Check within the compressed trie node
		elsif ($childs_type eq 'ARRAY') {
			my ($edge_match, $edge_mismatch, $key_mismatch, $child) = $node->edges->match(substr($key, $key_iter));

			#The new key contains all of the old key
			if ($edge_match && ! $edge_mismatch) {
				$node = $child;
				$key_iter += length($edge_match);

			#The old key contains all of the new key
			} elsif ($edge_match && ! $key_mismatch) {
				#Create a new trie containing the unmatched suffix of the matched key and its sub-trie
				my $new_node = [];
				$new_node->edges->names($edge_mismatch);
				$new_node->edges>nodes($node->edges->nodes);
				$node = $new_node;
				last;
			#There was a mismatch in the comparison so the key doesn't exist
			} else { $node = undef; last }

		#Keep expanding down the trie
		} else {
			$node = $node->edges->addEdge($key};
			++$key_iter;
		}
	}

	return $node ? $make_new_trie_ref->($node, $self) : undef;
}
*lookup = \&find;

#Get a Tree::SEMETrie::Iterator for efficient trie traversal
sub iterator { Tree::SEMETrie::Iterator->new($_[0]) }

#Trie Operators

#Inserts a unique path into the trie given a key.  If the full key already exists,
#the function returns false.  Any arbitrary value may be stored at the end of the path.
sub add {
	my $self = shift;
	my ($key, $value) = @_;

	#No path should ever exist for undef
	return unless defined $key;

	my $node = $self;

	my ($key_iter, $key_length) = (0, length $key);
	while ($key_iter < $key_length) {
		my $childs_type = ref($node->[$CHILDS]);

		#There are no branches so we've found a new key
		if (! $childs_type) {
			#Create a new branch for the suffix and move down the trie
			my $single_child = $node->[$CHILDS] = [];

			$single_child->[$SINGLE_CHILD_KEY] = substr($key, $key_iter);
			$node = $single_child->[$SINGLE_CHILD_NODE] = [];
			last;

		#There is exactly 1 current branch
		} elsif ($childs_type eq 'ARRAY') {

			#Determine where the keys match
			my $old_key = $node->[$CHILDS][$SINGLE_CHILD_KEY];
			my $old_key_length = length $old_key;
			my $match_length = $find_match_length_ref->(substr($key, $key_iter), $old_key);

			#The new key contains all of the old key
			if($match_length == $old_key_length) {
				$node = $node->[$CHILDS][$SINGLE_CHILD_NODE];
				$key_iter += $match_length;

			#The old key contains all of the new key
			} elsif($match_length == $key_length - $key_iter) {

				#Fetch and save the current child branch so that we can split it
				my $old_single_child = $node->[$CHILDS];
				#The unmatched suffix still points to the same trie
				$old_single_child->[$SINGLE_CHILD_KEY] = substr($old_key, $match_length);

				#Create a new branch point
				my $new_single_child = $node->[$CHILDS] = [];
				#Insert the matched prefix
				$new_single_child->[$SINGLE_CHILD_KEY] = substr($key, $key_iter);
				#Move down the trie to the newly inserted branch point
				$node = $new_single_child->[$SINGLE_CHILD_NODE] = [];
				#Make the unmatched suffix a subtrie of the matched prefix
				$node->[$CHILDS] = $old_single_child;
				last;

			} else {

				my ($key_match, $old_key_diff, $old_key_tail) = $split_string_at_position_ref->($old_key, $match_length);
				my $new_key_diff = substr($key, $key_iter + $match_length, 1);

				#Fetch and save the current child branch so that we can split it later
				my $old_single_child = $node->[$CHILDS];

				#The match may occur in the middle
				if ($key_match ne '') {
					#Create a new branch to represent the match
					my $match_childs_ref = $node->[$CHILDS] = [];
					$match_childs_ref->[$SINGLE_CHILD_KEY] = $key_match;
					#Move down the branch to the end fo the match
					$node = $match_childs_ref->[$SINGLE_CHILD_NODE] = [];
				}

				#Create a new branch to represent the divergence
				my $branch_childs_ref = $node->[$CHILDS] = {};

				#The match may occur at the end of the old key, so the old key's child becomes the divergence's child
				if ($old_key_tail eq '') {
					$branch_childs_ref->{$old_key_diff} = $old_single_child->[$SINGLE_CHILD_NODE];

				#Otherwise make the old branch a child of the old branch's divergence point
				} else {
					#Replace the old key with the suffix after the difference
					$old_single_child->[$SINGLE_CHILD_KEY] = $old_key_tail;
					$branch_childs_ref->{$old_key_diff}[$CHILDS] = $old_single_child;
				}

				#Make the new branch a child of the new branch's divergence point
				$node = $branch_childs_ref->{$new_key_diff} = [];

				#Move past the branch point
				$key_iter += $match_length + 1;
			}

		#Otherwise this node has multiple branches
		} else {
			#Retrieve the next node in the trie, creating a new one when necessary
			$node = $node->[$CHILDS]{substr($key, $key_iter, 1)} ||= [];
			++$key_iter;
		}
	}

	#Return success/fail
	if (! $node->[$VALUE]) {
		${$node->[$VALUE]} = $value;
		return 1;
	}
	return 0;
}
*insert = \&add;

#Removes a path from the trie.  Returns the value stored at the end of the path.
sub erase {
	my $self = shift;
	my ($key) = @_;

	my $grand_parent_node = undef;
	my $parent_node = undef;
	my $node = $self;

	my ($key_iter, $key_length) = (0, length $key);
	while ($key_iter < $key_length) {
		my $childs_type = ref($node->[$CHILDS]);

		#Key does not exist since we're at the end of the trie
		if (! $childs_type) { $node = undef; last }

		#Check within the compressed trie node
		elsif ($childs_type eq 'ARRAY') {

			#Determine where the keys match
			my $old_key = $node->[$CHILDS][$SINGLE_CHILD_KEY];
			my $old_key_length = length $old_key;
			my $match_length = $find_match_length_ref->(substr($key, $key_iter), $old_key);

			#The deleted key contains all of the old key
			if($match_length == $old_key_length) {

				#Save the parent
				$grand_parent_node = $parent_node;
				$parent_node = $node;
				#Move to the end of the compressed node
				$node = $node->[$CHILDS][$SINGLE_CHILD_NODE];
				#Move to the next part of the key
				$key_iter += $match_length;

			#There was a mismatch in the comparison so the deleted key doesn't exist
			} else { $node = undef; last }

		#Keep expanding down the trie
		} else {

			#Save the parent
			$grand_parent_node = $parent_node;
			$parent_node = $node;
			#Move to the next node
			$node = $node->[$CHILDS]{substr($key, $key_iter, 1)};
			++$key_iter;
		}
	}

	my $deleted_value;
	if ($node && $node->[$VALUE]) {
		$deleted_value = ${delete $node->[$VALUE]};

		my $childs_type = ref($node->[$CHILDS]);

		#The node has no children
		if (! $childs_type) {
			my $parent_childs_ref = $parent_node->[$CHILDS];
			my $parent_childs_type = ref($parent_childs_ref);

			#The node may have siblings
			if ($parent_childs_type eq 'HASH') {
				#Final character of the key must be the branch point
				delete $parent_childs_ref->{substr($key, -1)};

				#The sibling may now be an only child
				if (keys(%$parent_childs_ref) == 1) {
					#Fix the representation
					$parent_node->[$CHILDS] = [];
					@{$parent_node->[$CHILDS]}[$SINGLE_CHILD_KEY, $SINGLE_CHILD_NODE] = each %$parent_childs_ref;

					#Try to repair the divergence, which splits a key into 3
					$compress_trie_ref->($parent_node->[$CHILDS][$SINGLE_CHILD_NODE], $parent_node);
					$compress_trie_ref->($parent_node, $grand_parent_node);
				}

			#The node has no siblings
			} else {
				delete $parent_node->[$CHILDS];
			}

		#The node has 1 child
		} elsif ($childs_type eq 'ARRAY') {
			$compress_trie_ref->($node, $parent_node);
		}
	}

	return $deleted_value;
}
*remove = \&erase;


sub merge {
	my $self = shift;
	my ($key, $trie, $choice_ref) = @_;
	$choice_ref ||= $merge_choice_ref;

	my $preexisting_value = $self->add($key);
	my $merge_point = $self->find($key);

	my $childs_type = ref($merge_point->[$CHILDS]);
	if (! $childs_type) {
		$merge_point->[$CHILDS] = $trie->[$CHILDS];

		$merge_point->[$VALUE] = $preexisting_value
			? $trie->[$VALUE]
			: $choice_ref->($merge_point->[$VALUE], $trie->[$VALUE]);
		$compress_trie_ref->($merge_point->[$CHILDS][$SINGLE_CHILD_NODE], $merge_point)
			if ref($merge_point->[$CHILDS]) eq 'ARRAY';

	#We need to consider how to merge
	} else {
		#both single
		#
		#both multi
		#
		#

		#m-om-my - asdga
		#     ma - sdaa
		#=
		#m-om-m-y-asdga
		#       a-sdaa
		#
		#m-om-may
		#m-om m-a
		#     d-ad
		#=
		#m-om-m-a-y
		#     d-ad
		#
		#m-om-m-y
		#     m-as
		#m-om m-a
		#     d-ad
		#=
		#m-om-m-y
		#       a-s
		#     d-ad

	}

}

#Remove the entire subtrie with a given path.  Returns the removed
sub prune {
	my $self = shift;
	my ($key) = @_;

	my $grand_parent_node = undef;
	my $parent_node = undef;
	my $node = $self;

	my ($key_iter, $key_length) = (0, length $key);
	while ($key_iter < $key_length) {
		my $childs_type = ref($node->[$CHILDS]);

		#Key does not exist since we're at the end of the trie
		if (! $childs_type) { $node = undef; last }

		#Check within the compressed trie node
		elsif ($childs_type eq 'ARRAY') {

			#Determine where the keys match
			my $old_key = $node->[$CHILDS][$SINGLE_CHILD_KEY];
			my $old_key_length = length $old_key;
			my $match_length = $find_match_length_ref->(substr($key, $key_iter), $old_key);

			#The pruning key contains all of the old key
			if($match_length == $old_key_length) {

				#Save the parent
				$grand_parent_node = $parent_node;
				$parent_node = $node;
				#Move to the end of the compressed node
				$node = $node->[$CHILDS][$SINGLE_CHILD_NODE];
				#Move to the next part of the key
				$key_iter += $match_length;

			#The old key contains all of the pruning key
			} elsif($match_length == $key_length - $key_iter) {

				#Create a new trie containing the unmatched suffix of the matched key and its sub-trie
				my $new_node = [undef, [substr($old_key, $match_length) => $node->[$CHILDS][$SINGLE_CHILD_NODE]]];

				#Save the parent
				$grand_parent_node = $parent_node;
				$parent_node = $node;
				#Kill the dangling edge
				delete $node->[$CHILDS];
				$node = $new_node;

				last;
			} else { $node = undef; last }

		#Keep expanding down the trie
		} else {

			#Save the parent
			$grand_parent_node = $parent_node;
			$parent_node = $node;
			#Move to the next node
			$node = $node->[$CHILDS]{substr($key, $key_iter, 1)};
			++$key_iter;
		}
	}

	my $pruned_trie;
	if ($node && $node->[$CHILDS]) {
		my $new_trie = [];
		$new_trie->[$CHILDS] = ${delete $node->[$CHILDS]};
		$pruned_trie = $make_new_trie_ref->($new_trie);
		$compress_trie_ref->($parent_node, $grand_parent_node);
	}

	return $pruned_trie;
}

1;
