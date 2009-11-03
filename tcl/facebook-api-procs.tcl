# packages/facebook-api/tcl/facebook-api-procs.tcl

ad_library {
    
    Implements Facebook REST XML API
    with Tcl helper procedures to handle caching, timeouts, etc...

    Also manages application keys.
    
    @author Dave Bauer (dave@thedesignexperience.org)
    @creation-date 2007-08-20
    @cvs-id $Id$

}

namespace eval facebook_api {}

# ***************************
# Core procs
# - almost all the other procs in this library
#  will need to use any of the following procedures
# ***************************

ad_proc facebook_api::get_package_id {

} {
    Returns the package_id of this facebook app

    @return package_id
} {
    return [ad_conn package_id]
}

ad_proc facebook_api::api_key {
    -package_key
} {
    Get the Facebook API key given the package_key of
        the openacs package.
    The openacs package that you will use as a facebook app
        must have an "ApiKey" parameter defined in acs-admin/apm.
    
    @return API key
    
} {
    return [parameter::get_from_package_key -package_key $package_key -parameter "ApiKey"]
}

ad_proc facebook_api::secret {
    -package_key
} {
    Get the Facebook API secret given the package_key of
        the openacs package.
    The openacs package that you will use as a facebook app
        must have a "secret" parameter defined in acs-admin/apm.

    @return Secret
} {
    return [parameter::get_from_package_key -package_key $package_key -parameter "secret"]
}

ad_proc facebook_api::request_url {
} {
    URL of facebook API

    @return URL
} {
    return "http://api.facebook.com/restserver.php"
}

ad_proc facebook_api::do_request {
    -method
    -params
    -package_key
    {-session_key ""}
} {
    Make a request to Facebook API

    @param method Facebook API Method
    @param params list of key value pairs of parameters to pass to the method
    @return XML response

} {
    set api_key [api_key -package_key $package_key]
    lappend params call_id [get_call_id]
    lappend params api_key $api_key v "1.0"
    lappend params method $method
    set params [sort_params $params]
    set sig [sig -package_key $package_key $params]
    lappend params sig $sig
    set result "[util_httppost [request_url] [format_post_vars $params]]"
}

ad_proc facebook_api::sig {
    -package_key
    params
} {
    @param parms list of key value pairs of parameters to pass to the method
    @return sig formatted for Facebook API
} {
    set sig ""
    set params_list [list]
    foreach {key value} $params {
        append sig "${key}=${value}"
    }
    append sig "[secret -package_key $package_key]"
    package require md5

    #
    # WARNING: md5 hex string MUST be in lowercase or Facebook will reject
    # the signature
    # 

    return [string tolower [md5::md5 -hex $sig]]
}

ad_proc facebook_api::get_call_id {
} {
    @return Unique integer for call_id
} {
    return [string trim [clock clicks -milliseconds] -]
}

ad_proc facebook_api::login {
    -package_key
} {
    @return Login Status
} {
    ad_returnredirect http://www.facebook.com/login.php?api_key=[api_key -package_key $package_key]&v=1.0
}

ad_proc facebook_api::format_post_vars {
    params
} {
    @param list of key value pairs in array get format
    @return formatted key=value&key=value...
} {
    set params_list [list]
    foreach {key value} $params {
        lappend params_list [list $key $value]
    }
    return [export_vars $params_list]
}

ad_proc facebook_api::sort_params {
    params
} {

} {
    set params_list [list]
    foreach {key value} $params {
        lappend params_list [list $key $value]
    }
    set params [list]
    foreach l [lsort -index 0 $params_list] {
        lappend params [lindex $l 0] [lindex $l 1]
    }
    return $params
}

ad_proc facebook_api::get_session_from_token {
    -package_key
    -auth_token
    {-url ""}
} {
    Returns a new session_id from facebook using the given token. If a url is specified, this proc will redirect the user to the specified url.
} {
    # fetch session info
    set json [facebook_api::do_request -package_key $package_key -method auth.getSession -params [list auth_token $auth_token format json]]
    # record session info for the fb user
    set session_data [json::json2dict $json]
    set session_key [lindex $session_data 1]
    set uid [lindex $session_data 3]
    set session_expires [lindex $session_data 5]
    if { [db_0or1row "check_fb_user" "select uid from fb_users where uid=:uid"] } {
        db_dml "update_session_info" "update fb_users set auth_token=:auth_token, session_key=:session_key, session_expires=:session_expires where uid=:uid"
    } else {
        db_dml "record_session_info" "insert into fb_users (uid,auth_token,session_key,session_expires) values (:uid,:auth_token,:session_key,:session_expires)"
    }
    # check if the user is logged in to this oacs site
    # if yes, then create a map between the user_id and the fb_uid
    set user_id [ad_conn user_id]
    if {  $user_id != 0 && ![db_0or1row "checkmap" "select uid from oacs_fb_user_map where user_id=:user_id"]} {
        db_dml "map_fb_uid" "insert into oacs_fb_user_map (user_id,uid) values (:user_id,:uid)"
    }
    if { [exists_and_not_null url] } {
        facebook_api::redirect $url
    } else {
        return [list $session_key $uid $session_expires]
    }
}

ad_proc facebook_api::json_to_multirow {
    -json
    -multirow
} {
    Convert JSON to a multirow
} {
    set list_data [json::json2dict $json]
    template::multirow create $multirow
    set i 1
    foreach elm $list_data {
        array set arr_data $elm
        template::multirow append $multirow
        foreach name [array names arr_data] {
            if {[lsearch [template::multirow columns $multirow] $name] < 0} {
            template::multirow extend $multirow $name
            }
            template::multirow set $multirow $i $name $arr_data($name)
        }
        incr i
    }
}

ad_proc facebook_api::redirect {
    url
} {
    Break out of frames
} {
    ns_return 200 text/html "
<html>
<head>
<script type=\"text/javascript\">
top.location.href=\"${url}\";
</script>
</head>
<body>
</body>
</html>
"
    ad_script_abort
}

ad_proc facebook_api::get_user_or_redirect {
    -package_key
    -session_key
    -uid
} {
    Returns array list of user info or redirects user to add the app
    if they are not a user
} {
    set user [facebook_api::get_current_user_info -package_key $package_key -session_key $session_key -uid $uid]

    set user_info_list [json::json2dict $user]

    if { [llength $user_info_list]==0 || [lindex $user_info_list 0] == "error_code" } {
        facebook_api::redirect "http://www.facebook.com/add.php?api_key=[api_key -package_key $package_key]"
    } else {
        array set user_array [lindex $user_info_list 0]
        return $user
    }
}

# ***************************
# Request procs
# - procs that request some user information
# ***************************

ad_proc facebook_api::get_current_user_info {
    -package_key
    -session_key
    {-fields "uid,name,first_name,last_name,status,pic_square,pic,about_me,sex,hometown_location,hs_info,interests,movies,music,political,quotes,religion,has_added_app"}
    -uid
} {
    Get the user information of the current user.
    http://wiki.developers.facebook.com/index.php/Users.getInfo
} {
    return [facebook_api::do_request -package_key $package_key -method "users.getInfo" -params [list session_key $session_key uids $uid fields $fields format json]]
}

ad_proc facebook_api::get_friend_ids {
    -package_key
    -session_key
    {-format json}
} {
    Get a Tcl list of friend user_ids
    http://wiki.developers.facebook.com/index.php/Friends.get
} {
    return [split [string trim [facebook_api::do_request -package_key $package_key -method "friends.get" -params [list session_key $session_key format $format]] \[\]] ","]   
}

ad_proc facebook_api::get_friends_info {
    -package_key
    {-fields "name,first_name,last_name,status,pic_square,pic,about_me,sex,has_added_app,uid"}
    -session_key
    {-format json}
} {
    Get a JSON array of users info
    http://wiki.developers.facebook.com/index.php/Users.getInfo
} {
    set friends [get_friend_ids -package_key $package_key -session_key $session_key]
    return [facebook_api::do_request -package_key $package_key -method "users.getInfo" -params [list session_key $session_key uids [join $friends ","] fields $fields format $format]]
}

ad_proc facebook_api::are_friends {
    -package_key
    -friend_ids
    -session_key
} {
    List of lists id1 id2 friends_p
} {
    set all_friends [list]
    set all_friends2 [list]
    set loadedcombo [list]
    # we need to make a list of every combination
    foreach f $friend_ids {
        foreach f2 $friend_ids {
            if { [lsearch -exact $loadedcombo "${f2}${f}"] == -1 && [lsearch -exact $loadedcombo "${f}${f2}"] == -1} {
                lappend all_friends $f
                lappend all_friends2 $f2
                lappend loadedcombo ${f2}${f}
            }
        }
    }
    return [facebook_api::do_request -package_key $package_key -method "friends.areFriends" -params [list session_key $session_key uids1 [join $all_friends ","] uids2 [join $all_friends2 ","] format json]]
}

ad_proc facebook_api::get_groups_info {
    -package_key
    -session_key
    {-format json}
} {
    Get a JSON array of groups info
    http://wiki.developers.facebook.com/index.php/Groups.get
} {
    return [facebook_api::do_request -package_key $package_key -method "groups.get" -params [list session_key $session_key format $format]]
}

ad_proc facebook_api::get_group_members {
    -package_key
    -session_key
    -gid
    {-format json}
} {
    Get the uids of the members of a group
    http://wiki.developers.facebook.com/index.php/Groups.getMembers
} {
    return [facebook_api::do_request -package_key $package_key -method "groups.getMembers" -params [list session_key $session_key gid $gid format $format]]
}

# ***************************
# Photo procs
# - procs to retrieve facebook photos
# ***************************

ad_proc facebook_api::photo_getalbums {
    -package_key
    -session_key
    -uid
    {-format "json"}
} {
    Returns a list of facebook photo albums from a user with the give uid
    http://developer.facebook.com/documentation.php?v=1.0&method=photos.getAlbums
} {
    return [facebook_api::do_request -package_key $package_key -method "photos.getAlbums" -params [list session_key $session_key uid $uid format $format]]
}

ad_proc facebook_api::photo_getphotos {
    -package_key
    -session_key
    {-subj_id ""}
    {-aid ""}
    {-pids ""}
    {-format "json"}
} {
    Returns a list of photos
    http://developer.facebook.com/documentation.php?v=1.0&method=photos.get
} {
    set params [list session_key $session_key format $format]
    if { [exists_and_not_null subj_id] } {
        lappend params "subj_id"
        lappend params $subj_id
    }
    if { [exists_and_not_null aid] } {
        lappend params "aid"
        lappend params $aid
    }
    if { [exists_and_not_null pids] } {
        lappend params "pids"
        lappend params $pids
    }
    return [facebook_api::do_request -package_key $package_key -method "photos.get" -params $params]
}


# ***************************
# Feed procs
# - procs related to publishing feeds to user's profile page
# ***************************


ad_proc facebook_api::set_fbml {
    -package_key
    -session_key
    -markup
} {
    Set profile FBML 
} {
    return [facebook_api::do_request -package_key $package_key -method "profile.setFBML" -params [list session_key $session_key markup $markup]]
}

ad_proc facebook_api::publish_feed_story {
    -package_key
    -session_key
    -title
    -body
} {
    Publish a story to user's feed
} {
    return [facebook_api::do_request -package_key $package_key -method "feed.publishStoryTouser" -params [list session_key $session_key title $title body $body]]
}

ad_proc facebook_api::publish_user_action {
    -package_key
    -session_key
    -title
    -body
} {
    Publish a user action to user's feed
} {
    return [facebook_api::do_request -package_key $package_key -method "feed.publishActionOfUser" -params [list session_key $session_key title $title body $body]]
}

ad_proc facebook_api::publish_templatized_action {
    -package_key
    -session_key
    -title
    -body
} {
    Publish a templatized story to user's feed
} {
    return [facebook_api::do_request -package_key $package_key -method "feed.publishTemplatizedAction" -params [list session_key $session_key title $title body $body]]
}

# ***************************
# Custom procs
# - we're going to add some useful features to
#  this api, e.g. scoring, caching user info
# - note some of this are not yet fully functional
# ***************************

ad_proc facebook_api::score_friends {
    -friend_ids
    -session_key
} {
    Score friends

    @return list of lists {friend1 friend2 friend_p}
} {
    # do requests if they arent in the db
    
}

ad_proc facebook_api::save_are_friends {
    -package_key
    -friend_ids
    -session_key
} {
    Save friend of friend data
    
    @return JSON data from are_friends
} {
    set json [facebook_api::are_friends -package_key $package_key \
		  -friend_ids $friend_ids \
		  -session_key $session_key]
    ad_return_complaint 1 [json::json2dict $json]

    return $json
}

ad_proc facebook_api::add_user {
    -uid
} {
    Add a user
} {
    # ns_log notice "Add user"
    if {![facebook_api::uid_exists -uid $uid]} {
	    db_dml add_user "insert into fb_users (uid) values (:uid)"
        # ns_log notice "Adding uid $uid"
	    db_flush_cache -cache_key_pattern $uid
    }
}

ad_proc facebook_api::uid_exists {
    -uid
} {
    Have we seen this uid before?
} {
    return [db_string -cache_key $uid uid_exists "select 1 from fb_users where uid=:uid" -default 0]
}

ad_proc facebook_api::update_friends_p {
    -uid
} {
    
} {
    return [db_string -cache_key $uid get_last_updated "select ((last_friends_update is null) or (last_friends_update < (current_timestamp - ('1 day' :: interval) ))) from fb_users where uid=:uid" -default "0"]
}

ad_proc facebook_api::update_friends {
    -uid
    -session_key
    -package_key
} {
    Update the list of this users friends in our database
} {
    if {![facebook_api::update_friends_p -uid $uid]} {
        return
    }
    set friends [get_friend_ids -session_key $session_key -package_key $package_key]
    foreach f $friends {
        if {![db_0or1row get_friend "select 1 from fb_friends where uid=:uid and friend_uid = :f"]} {
            db_dml add_friend "insert into fb_friends (uid,friend_uid) values (:uid,:f)"
        }
    }
    db_dml update_last "update fb_users set last_friends_update = current_timestamp where uid = :uid"
    db_flush_cache -cache_key_pattern $uid
}