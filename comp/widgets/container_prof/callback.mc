<%args>
$widget
$field
$param
</%args>

<%once>

###############
## Constants ##

my $STORY_URL = '/workflow/profile/story';
my $CONT_URL  = '/workflow/profile/story/container';
my $MEDIA_URL = '/workflow/profile/media';
my $MEDIA_CONT = '/workflow/profile/media/container';

my $regex = { "\n" => qr/\s*\n\n|\r\r\s*/,
	      '<p>' => qr/\s*<p>\s*/,
	      '<br>' => qr/\s*<br>\s*/,
	    };

###############
## Packages  ##
my %pkgs = ( story => get_package_name('story'),
	     media => get_package_name('media')
	   );


####################
## Misc Functions ##

my $push_tile_stack = sub {
    my ($widget, $new_tile) = @_;

    # Push the current tile onto the stack.
    my $tiles    = get_state_data($widget, 'tiles');
    my $cur_tile = get_state_data($widget, 'tile');
    push @$tiles, $cur_tile;

    my $crumb = '';
    foreach my $t (@$tiles[1..$#$tiles]) {
	$crumb .= ' &quot;' . $t->get_name . '&quot;' . ' |';
    }
    $crumb .= ' &quot;' . $new_tile->get_name . '&quot;';

    set_state_data($widget, 'crumb', $crumb);
    set_state_data($widget, 'tiles', $tiles);
    set_state_data($widget, 'tile', $new_tile);
};

my $pop_tile_stack = sub {
    my ($widget) = @_;

    my $tiles = get_state_data($widget, 'tiles');
    my $parent_tile = pop @$tiles;

    my $crumb = '';
    foreach my $t (@$tiles[1..$#$tiles]) {
		$crumb .= ' &quot;' . $t->get_name . '&quot;' . ' |';
    }
    $crumb .= ' &quot;' . $parent_tile->get_name . '&quot;';

    set_state_data($widget, 'crumb', $crumb);
    set_state_data($widget, 'tile', $parent_tile);
    set_state_data($widget, 'tiles', $tiles);
    return $parent_tile;
};

my $pop_and_redirect = sub {
    my ($widget, $flip) = @_;
    my $tile;

    # Get the tile stack and pop off the current tile.
    $tile = $flip ? get_state_data($widget, 'tile')
                  : $pop_tile_stack->($widget);

    my $object_type = $tile->get_object_type;

    # If our tile has parents, show the regular edit screen.
    if ($tile->get_parent_id) {
	my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
	my $page = get_state_name($widget) eq 'view' ? '' : 'edit';

	#  Don't redirect if we're already at the right URI
	set_redirect("$uri/$page") unless $r->uri eq "$uri/$page";
    }
    # If our tile doesn't have parents go to the main story edit screen.
    else {
	my $uri = $object_type eq 'media' ? $MEDIA_URL : $STORY_URL;
	set_redirect($uri);
    }
};

my $delete_element = sub {
    my ($widget, $new_tile) = @_;
    my $tile = get_state_data($widget, 'tile');
    my $parent = $pop_tile_stack->($widget);
    $parent->delete_tiles( [ $tile ]);
    $parent->save();
    my $object_type = $parent->get_object_type;

    # if our tile has parents, show the regular edit screen.
    if ($parent->get_parent_id) {
        my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
        my $page = get_state_name($widget) eq 'view' ? '' : 'edit';

        #  Don't redirect if we're already at the right URI
        set_redirect("$uri/$page") unless $r->uri eq "$uri/$page";
    }
    # If our tile doesn't have parents go to the main story edit screen.
    else {
        my $uri = $object_type eq 'media' ? $MEDIA_URL : $STORY_URL;
        set_redirect($uri);
    }

    add_msg("Element &quot;" . $tile->get_name . "&quot; deleted.");
    return;
};


my $update_parts = sub {
    my ($widget, $param, $locate_id) = @_;
    my $tile = get_state_data($widget, 'tile');
    my $locate_tile;

    # Don't delete unless either the 'Save...' or 'Delete' buttons were pressed
    my $do_delete = ($param->{$widget.'|delete_cb'} ||
		     $param->{$widget.'|save_and_up_cb'} ||
		     $param->{$widget.'|save_and_stay_cb'});

    my (@curr_tiles, @delete);

    # Save data to tiles and put them in a useable order
    foreach ($tile->get_tiles()) {
	my $id = $_->get_id();

	# Grab the tile we're looking for
	local $^W = undef;
	$locate_tile = $_ if $id == $locate_id;
	if ($do_delete && ($param->{"$widget|delete_cont$id"} ||
			   $param->{"$widget|delete_data$id"})) {
	    add_msg("Element &quot;" . $_->get_name . "&quot; deleted.");
	    push @delete, $_;
	    next;
	}

	my ($order, $redir);
	if ($_->is_container) {
	    $order = $param->{"$widget|reorder_con$id"};
	} else {
	    $order = $param->{"$widget|reorder_dat$id"};
	    my $val = $param->{"$widget|$id"} || '';
	    if ( $param->{"$widget|${id}-partial"} ) {
		# The date is only partial. Send them back to to it again.
		add_msg("Invalid date value for &quot;" . $_->get_name
			. "&quot; field.");
		set_state_data($widget, '__NO_SAVE__', 1);
	    } else {
		# Truncate the value, if necessary, then set it.
		my $max = $_->get_element_data_obj->get_meta('html_info')->{maxlength};
		$val = substr($val, 0, $max) if $max && length $val > $max;
		$_->set_data($val);
	    }
	}

	$curr_tiles[$order] = $_;
    }

    # Delete tiles as necessary.
    $tile->delete_tiles(\@delete) if $do_delete;

    if (@curr_tiles) {
    	eval { $tile->reorder_tiles([grep(defined($_), @curr_tiles)]) };
    	if ($@) {
	    add_msg("Warning! State inconsistant: Please use the buttons "
		    . "provided by the application rather than the "
		    . "'Back'/'Forward' buttons.");
	    return;
    	}
    }

    set_state_data($widget, 'tile', $tile);
    return $locate_tile;
};

my $save_data = sub {
    my ($widget) = @_;

    my $tile   = get_state_data($widget, 'tile');
    my $field  = get_state_data($widget, 'field');
    my $dtiles = get_state_data($widget, 'dtiles') || [];
    my $data   = get_state_data($widget, 'data');

    # Get the asset type data object.
    my $at_id = $tile->get_element_id;
    my $at    = Bric::Biz::AssetType->lookup({'id' => $at_id});
    my $atd   = $at->get_data($field);

    foreach my $d (@$data) {
	my $dt;

	if (@$dtiles) {
	    # Fill the existing tiles first.
	    $dt = shift @$dtiles;
	} else {
	    # Otherwise create new tiles.
	    $dt = Bric::Biz::Asset::Business::Parts::Tile::Data->new(
					       {'element_data' => $atd,
						'object_type'     => 'story'});
	    $tile->add_tile($dt);
	}

	# Set the data on this tile.
	$dt->set_data($d);
    }

    # Delete any remaining tiles that haven't been filled.
    $tile->delete_tiles($dtiles) if scalar(@$dtiles);

    # Save the tile
    $tile->save;

    # Grab only the tiles that have the name $field
    my @dtiles = grep($_->get_name eq $field, $tile->get_tiles());

    set_state_data($widget, 'dtiles', \@dtiles);
};

my $split_fields = sub {
    my ($widget, $text) = @_;
    my $sep = get_state_data($widget, 'separator');
    my @data;

    # Change Windows newlines to Unix newlines.
    $text =~ s/\r\n/\n/g;

    # Grab the split regex.
    my $re = $regex->{$sep} ||= qr/\s*\Q$sep\E\s*/;

    # Split 'em up.
    @data = map { s/^\s+//;        # Strip out beginning spaces.
		  s/\s+$//;        # Strip out ending spaces.
		  s/[\n\t\r\f]//g; # Strip out unwanted charactes.
		  s/\s{2,}/ /g;    # Strip out double-spaces.
	          $_;
	      } split(/$re/, $text);

    # Save 'em.
    set_state_data($widget, 'data', \@data);
};

my $drift_correction = sub {
    my ($widget, $param) = @_;
    # Don't do anything if we've already corrected ourselves.
    return if $param->{'_drift_corrected_'};;

    # Update the state name
    set_state_name($widget, $param->{$widget.'|state_name'});

    # Get the tile ID this page thinks its displaying.
    my $tile_id = $param->{$widget.'|top_stack_tile_id'};

    # Return if the page doesn't send us a tile_id
    return unless $tile_id;

    my $tile  = get_state_data($widget, 'tile');
    # Return immediately if everything is already in sync.
    if ($tile->get_id == $tile_id) {
	$param->{'_drift_corrected_'} = 1;
	return;
    }

    my $stack = get_state_data($widget, 'tiles');
    my @tmp_stack;

    while (@$stack > 0) {
	# Get the next tile on the stack.
	$tile = pop @$stack;
	# Finish this loop if we find our tile.
	last if $tile->get_id == $tile_id;
	# Push this tile on our temp stack just in case we can't find our ID.
	unshift @tmp_stack, $tile;
	# Undef the tile since its not the one we're looking for.
	$tile = undef;
    }

    # If we found the tile, make it the head tile and save the remaining stack.
    if ($tile) {
	set_state_data($widget, 'tile', $tile);
	set_state_data($widget, 'tiles', $stack);
    }
    # If we didn't find the tile, abort, and restore the tile stack
    else {
	add_msg("Warning! State inconsistant: Please use the buttons provided "
	        ."by the application rather than the 'Back'/'Forward' buttons");

	# Set this flag so that nothing gets changed on this request.
	$param->{'_inconsistant_state_'} = 1;

	set_state_data($widget, 'tiles', \@tmp_stack);
    }

    # Drift has now been corrected.
    $param->{'_drift_corrected_'} = 1;
};

#######################
## Callback Handlers ##

my $handle_clear = sub {
    my ($widget, $field, $param) = @_;

    # Clear out the state.
    clear_state($widget);
};

my $handle_add_element = sub {
    my ($widget, $field, $param) = @_;

    # Add Element(s) to this container tile

    # get the tile
    my $tile = get_state_data($widget, 'tile');
    my $key = $tile->get_object_type;
    # Get this tile's asset object if it's a top-level asset.
    my $a_obj;
    if ( Bric::Biz::AssetType->lookup({ 
			id => $tile->get_element_id })->get_top_level) {
		$a_obj = $pkgs{$key}->lookup({ id => $tile->get_object_instance_id});
    }
    my $fields = mk_aref($param->{"$widget|add_element"});

    foreach my $f (@$fields) {
	my ($type,$id) = unpack('A5 A*', $f);
	my $at;
	if ($type eq 'cont_') {
	    $at = Bric::Biz::AssetType->lookup({id=>$id});
	    my $cont = $tile->add_container($at);
	    $tile->save();
	    $push_tile_stack->($widget, $cont);

	    if ($key eq 'story') {
		# Don't redirect if we're already at the edit page.
		set_redirect("$CONT_URL/edit.html")
		  unless $r->uri eq "$CONT_URL/edit.html";
	    } else {
		set_redirect("$MEDIA_CONT/edit.html")
		  unless $r->uri eq "$MEDIA_CONT/edit.html";
	    }

	} elsif ($type eq 'data_') {
	    $at = Bric::Biz::AssetType::Parts::Data->lookup({id=>$id});
	    $tile->add_data($at, '');
	    $tile->save();
	    set_state_data($widget, 'tile', $tile);
	}
	log_event($key . '_add_element', $a_obj, { Element => $at->get_name })
	  if $a_obj;
#       add_msg("Element &quot;".  $at->get_name . "&quot; added.");
    }
};

my $handle_update = sub {
    my ($widget, $field, $param) = @_;

    # Update the tile state data based on the parameter data.
    $update_parts->($widget, $param);
    my $tile = get_state_data($widget, 'tile');
    $tile->save();
};

my $handle_reorder = sub {
    # don't do anything, handled by the update_parts code now
};

my $handle_related_up = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');
    my $object_type = $tile->get_object_type;

    # If our tile has parents, show the regular edit screen.
    if ($tile->get_parent_id) {
	my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
	my $page = get_state_name($widget) eq 'view' ? '' : 'edit';

	#  Don't redirect if we're already at the right URI
	set_redirect("$uri/$page") unless $r->uri eq "$uri/$page";
    }
    # If our tile doesn't have parents go to the main story edit screen.
    else {
	my $uri = $object_type eq 'media' ? $MEDIA_URL : $STORY_URL;
	set_redirect($uri);
    }
    pop_page;
};

my $handle_pick_related_media = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');
    my $object_type = $tile->get_object_type;
    my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
    set_redirect("$uri/edit_related_media.html");
};

my $handle_relate_media = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');
    $tile->set_related_media($param->{$field});
    &$handle_related_up;
};

my $handle_unrelate_media = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');
    $tile->set_related_media(undef);
    &$handle_related_up;
};

my $handle_pick_related_story = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');
    my $object_type = $tile->get_object_type;
    my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
    set_redirect("$uri/edit_related_story.html");
};

my $handle_relate_story = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');
    $tile->set_related_instance_id($param->{$field});
    &$handle_related_up;
};

my $handle_unrelate_story = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');
    $tile->set_related_instance_id(undef);
    &$handle_related_up;
};

my $handle_lock_val = sub {
    my ($widget, $field, $param) = @_;
    my $autopop = ref $param->{$field} ? $param->{$field} : [$param->{$field}];
    my $tile    = get_state_data($widget, 'tile');

    # Map all the data tiles into a hash keyed by Tile::Data ID.
    my $data = { map { $_->get_id => $_ } 
		 grep(not($_->is_container), $tile->get_tiles) };

    foreach my $id (@$autopop) {
	my $lock_set = $param->{$widget.'|lock_val_'.$id} || 0;
	my $dt = $data->{$id};

	# Skip if there is no data tile here.
	next unless $dt;
	if ($lock_set) {
	    $dt->lock_val;
	} else {
	    $dt->unlock_val;
	}
    }
};

my $handle_delete = sub {
    my ($widget, $field, $param) = @_;
    # don't do anything Handled by the update parts code
};

my $handle_save_and_up = sub {
    my ($widget, $field, $param) = @_;

    if ($param->{"$widget|delete_element"}) {
	$delete_element->($widget);
	return;
    }

    if (get_state_data($widget, '__NO_SAVE__')) {
	# Do nothing.
	set_state_data($widget, '__NO_SAVE__', undef);
    } else {
	# Save the tile we are working on.
	my $tile = get_state_data($widget, 'tile');
	$tile->save();
	add_msg("Element &quot;" . $tile->get_name . "&quot; saved.");
	$pop_and_redirect->($widget);
    }
};

my $handle_save_and_stay = sub {
    my ($widget, $field, $param) = @_;
    if ($param->{"$widget|delete_element"}) {
	$delete_element->($widget);
	return;
    }

    if (get_state_data($widget, '__NO_SAVE__')) {
	# Do nothing.
	set_state_data($widget, '__NO_SAVE__', undef);
    } else {
	# Save the tile we are working on
	my $tile = get_state_data($widget, 'tile');
	$tile->save();
	add_msg("Element &quot;" . $tile->get_name . "&quot; saved.");
    }
};

my $handle_up = sub {
    my ($widget, $field, $param) = @_;
    $pop_and_redirect->($widget);
};

my $handle_default = sub {
    my ($widget, $field, $param) = @_;
    my $tile = get_state_data($widget, 'tile');

    if ($field =~ /^container_prof\|edit(\d+)_cb/ ) {
	# Update the existing fields and get the child tile matching ID $1
	my $edit_tile = $update_parts->($widget, $param, $1);

	# Push this child tile on top of the stack
	$push_tile_stack->($widget, $edit_tile);

	# Don't redirect if we're already on the right page.
	if ($tile->get_object_type eq 'media') {
	    unless ($r->uri eq "$MEDIA_CONT/edit.html") {
		set_redirect("$MEDIA_CONT/edit.html");
	    }
	} else {
	    unless ($r->uri eq "$CONT_URL/edit.html") {
		set_redirect("$CONT_URL/edit.html");
	    }
	}

    } elsif ($field =~ /^container_prof\|view(\d+)_cb/ ) {
	my ($view_tile) = grep(($_->get_id == $1), $tile->get_containers);

	# Push this child tile on top of the stack
	$push_tile_stack->($widget, $view_tile);

	if ($tile->get_object_type eq 'media') {
	    set_redirect("$MEDIA_CONT/") unless $r->uri eq "$MEDIA_CONT/";
	} else {
	    set_redirect("$CONT_URL/") unless $r->uri eq "$CONT_URL/";
	}
    } elsif ($field =~ /^container_prof\|bulk_edit-(\d+)_cb/) {
	my $tile_id   = $1;
	# Update the existing fields and get the child tile matching ID $tile_id
	my $edit_tile = $update_parts->($widget, $param, $tile_id);

	# Push the current tile onto the stack.
	$push_tile_stack->($widget, $edit_tile);

	# Get the name of the field to bulk edit
	my $field = $param->{$widget.'|bulk_edit_tile_field-'.$tile_id};

	# Save the bulk edit field name
	set_state_data($widget, 'field', $field);
	set_state_data($widget, 'view_flip', 0);
	set_state_name($widget, 'edit_bulk');

	if ($tile->get_object_type eq 'media') {
	    set_redirect("$MEDIA_CONT/edit_bulk.html");
	} else {
	    set_redirect("$CONT_URL/edit_bulk.html");
	}
    }
};

## The bulk edit handlers ##

my $handle_resize = sub {
    my ($widget, $field, $param) = @_;
    $split_fields->($widget, $param->{$widget.'|text'});
    set_state_data($widget, 'rows', $param->{$widget.'|rows'});
    set_state_data($widget, 'cols', $param->{$widget.'|cols'});
};

my $handle_change_sep = sub {
    my ($widget, $field, $param) = @_;
    my ($data, $sep);

    # Save off the custom separator in case it changes.
    set_state_data($widget, 'custom_sep', $param->{$widget.'|custom_sep'});

    # First split the fields along the old boundary character.
    $split_fields->($widget, $param->{$widget.'|text'});

    # Now load the new separator
    $sep = $param->{$widget.'|separator'};

    if ($sep ne 'custom') {
	set_state_data($widget, 'separator', $sep);
	set_state_data($widget, 'use_custom_sep', 0);
    } else {
	set_state_data($widget, 'separator', $param->{$widget.'|custom_sep'});
	set_state_data($widget, 'use_custom_sep', 1);
    }

    # Get the data and pass it back to be resplit against the new separator
    $data = get_state_data($widget, 'data');
    $sep  = get_state_data($widget, 'separator');
    $split_fields->($widget, join("\n$sep\n", @$data));
    add_msg("Seperator Changed.");
};

my $handle_recount = sub {
    my ($widget, $field, $param) = @_;
    $split_fields->($widget, $param->{$widget.'|text'});
};

my $handle_bulk_edit_this = sub {
    my ($widget, $field, $param) = @_;

    # Save the bulk edit field name
    set_state_data($widget, 'field', $param->{"$widget|bulk_edit_field"});

    # Note that we are just 'flipping' the current view of this tile.  That is,
    # its the same tile, same data, but different view of it.
    set_state_data($widget, 'view_flip', 1);

    set_state_name($widget, 'edit_bulk');
    my $tile = get_state_data($widget, 'tile');
    my $object_type = $tile->get_object_type();
    my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
    set_redirect("$uri/edit_bulk.html");
};

my $handle_bulk_save = sub {
    my ($widget, $field, $param) = @_;
    $split_fields->($widget, $param->{$widget.'|text'});
    $save_data->($widget);
    my $data_field = get_state_data($widget, 'field');
    add_msg("&quot;$data_field&quot; Elements saved.");
};

my $handle_bulk_up = sub {
    my ($widget, $field, $param) = @_;

    # Set the state back to edit mode.
    set_state_name($widget, 'edit');

    # Clear some values.
    set_state_data($widget, 'dtiles',   undef);
    set_state_data($widget, 'data',     undef);
    set_state_data($widget, 'field',    undef);

    # If the view has been flipped, just flip it back.
    if (get_state_data($widget, 'view_flip')) {
	# Set flip back to false.
	set_state_data($widget, 'view_flip', 0);
	$pop_and_redirect->($widget, 1);
    } else {
	$pop_and_redirect->($widget, 0);
    }
};

my $handle_bulk_save_and_up = sub {
    my ($widget, $field, $param) = @_;
    $split_fields->($widget, $param->{$widget.'|text'});
    my $data_field = get_state_data($widget, 'field');
    $save_data->($widget);
    $handle_bulk_up->($widget, $field, $param);
    add_msg("&quot;$data_field&quot; Elements saved.");
};

##########################
## Callback Definitions ##

my %cbs = (
	   # Clear out the state data
	   clear_pc            => $handle_clear,

	   # Add new fields or containers.
	   add_element_cb      => $handle_add_element,

	   # Update the container
	   update_pc           => $handle_update,

	   # Reorder the fields in this container
	   reorder_cb          => $handle_reorder,

	   # Relate media
	   pick_related_media_cb => $handle_pick_related_media,
	   relate_media_cb       => $handle_relate_media,
	   unrelate_media_cb     => $handle_unrelate_media,

	   # Relate stories
	   pick_related_story_cb => $handle_pick_related_story,
	   relate_story_cb       => $handle_relate_story,
	   unrelate_story_cb     => $handle_unrelate_story,

	   related_up_cb       => $handle_related_up,

	   lock_val_cb         => $handle_lock_val,

	   # Delete a field from this container.
	   delete_cb           => $handle_delete,

	   # Save the container and go up a level.
	   save_and_up_cb      => $handle_save_and_up,

	   # save and stay at the current level
	   save_and_stay_cb 	=> $handle_save_and_stay,

	   # Don't save and go up a level
	   up_cb               => $handle_up,

	   # Catch some special callbacks.
	   default             => $handle_default,

	   ##  The following callbacks apply to bulk edit specifically ##

	   # Resize the main text window
	   resize_cb           => $handle_resize,

	   # Change the separator string
	   change_sep_cb       => $handle_change_sep,

	   # Recount the number of words and bytes in the text window
           recount_cb          => $handle_recount,

	   # Enter bulk edit mode for the current tile.
	   bulk_edit_this_cb   => $handle_bulk_edit_this,

	   # Save the data but stay on the edit screen
	   bulk_save_cb        => $handle_bulk_save,

	   # Save the data and return to the previous page
	   bulk_save_and_up_cb => $handle_bulk_save_and_up,

	   # Do not save anything and return to the previous page
	   bulk_up_cb          => $handle_bulk_up,
	  );

</%once>

<%init>

$drift_correction->($widget, $param);

# Bail if we find that the state is inconsistant.
return if $param->{'_inconsistant_state_'};

my ($cb) = substr($field, length($widget)+1);

# Execute the call back if it exists.
if (exists $cbs{$cb}) {
    $cbs{$cb}->($widget, $field, $param);
} else {
    $cbs{'default'}->($widget, $field, $param);
}

</%init>

