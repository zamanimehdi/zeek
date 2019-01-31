##! Bro's OpenFlow control framework.
##!
##! This plugin-based framework allows to control OpenFlow capable
##! switches by implementing communication to an OpenFlow controller
##! via plugins. The framework has to be instantiated via the new function
##! in one of the plugins. This framework only offers very low-level
##! functionality; if you want to use OpenFlow capable switches, e.g.,
##! for shunting, please look at the NetControl framework, which provides higher
##! level functions and can use the OpenFlow framework as a backend.

module OpenFlow;

@load ./consts
@load ./types

export {
	## Global flow_mod function.
	##
	## controller: The controller which should execute the flow modification.
	##
	## match: The ofp_match record which describes the flow to match.
	##
	## flow_mod: The openflow flow_mod record which describes the action to take.
	##
	## Returns: F on error or if the plugin does not support the operation, T when the operation was queued.
	global flow_mod: function(controller: Controller, match: ofp_match, flow_mod: ofp_flow_mod): bool;

	## Clear the current flow table of the controller.
	##
	## controller: The controller which should execute the flow modification.
	##
	## Returns: F on error or if the plugin does not support the operation, T when the operation was queued.
	global flow_clear: function(controller: Controller): bool;

	## Event confirming successful modification of a flow rule.
	##
	## name: The unique name of the OpenFlow controller from which this event originated.
	##
	## match: The ofp_match record which describes the flow to match.
	##
	## flow_mod: The openflow flow_mod record which describes the action to take.
	##
	## msg: An optional informational message by the plugin.
	global flow_mod_success: event(name: string, match: ofp_match, flow_mod: ofp_flow_mod, msg: string &default="");

	## Reports an error while installing a flow Rule.
	##
	## name: The unique name of the OpenFlow controller from which this event originated.
	##
	## match: The ofp_match record which describes the flow to match.
	##
	## flow_mod: The openflow flow_mod record which describes the action to take.
	##
	## msg: Message to describe the event.
	global flow_mod_failure: event(name: string, match: ofp_match, flow_mod: ofp_flow_mod, msg: string &default="");

	## Reports that a flow was removed by the switch because of either the hard or the idle timeout.
	## This message is only generated by controllers that indicate that they support flow removal
	## in supports_flow_removed.
	##
	## name: The unique name of the OpenFlow controller from which this event originated.
	##
	## match: The ofp_match record which was used to create the flow.
	##
	## cookie: The cookie that was specified when creating the flow.
	##
	## priority: The priority that was specified when creating the flow.
	##
	## reason: The reason for flow removal (OFPRR_*).
	##
	## duration_sec: Duration of the flow in seconds.
	##
	## packet_count: Packet count of the flow.
	##
	## byte_count: Byte count of the flow.
	global flow_removed: event(name: string, match: ofp_match, cookie: count, priority: count, reason: count, duration_sec: count, idle_timeout: count, packet_count: count, byte_count: count);

	## Convert a conn_id record into an ofp_match record that can be used to
	## create match objects for OpenFlow.
	##
	## id: The conn_id record that describes the record.
	##
	## reverse: Reverse the sources and destinations when creating the match record (default F).
	##
	## Returns: ofp_match object for the conn_id record.
	global match_conn: function(id: conn_id, reverse: bool &default=F): ofp_match;

	# ###
	# ### Low-level functions for cookie handling and plugin registration.
	# ###

	## Function to get the unique id out of a given cookie.
	##
	## cookie: The openflow match cookie.
	##
	## Returns: The cookie unique id.
	global get_cookie_uid: function(cookie: count): count;

	## Function to get the group id out of a given cookie.
	##
	## cookie: The openflow match cookie.
	##
	## Returns: The cookie group id.
	global get_cookie_gid: function(cookie: count): count;

	## Function to generate a new cookie using our group id.
	##
	## cookie: The openflow match cookie.
	##
	## Returns: The cookie group id.
	global generate_cookie: function(cookie: count &default=0): count;

	## Function to register a controller instance. This function
	## is called automatically by the plugin _new functions.
	##
	## tpe: Type of this plugin.
	##
	## name: Unique name of this controller instance.
	##
	## controller: The controller to register.
	global register_controller: function(tpe: OpenFlow::Plugin, name: string, controller: Controller);

	## Function to unregister a controller instance. This function
	## should be called when a specific controller should no longer
	## be used.
	##
	## controller: The controller to unregister.
	global unregister_controller: function(controller: Controller);

	## Function to signal that a controller finished activation and is
	## ready to use. Will throw the ``OpenFlow::controller_activated``
	## event.
	global controller_init_done: function(controller: Controller);

	## Event that is raised once a controller finishes initialization
	## and is completely activated.
	## name: Unique name of this controller instance.
	##
	## controller: The controller that finished activation.
	global OpenFlow::controller_activated: event(name: string, controller: Controller);

	## Function to lookup a controller instance by name.
	##
	## name: Unique name of the controller to look up.
	##
	## Returns: One element vector with controller, if found. Empty vector otherwise.
	global lookup_controller: function(name: string): vector of Controller;
}

global name_to_controller: table[string] of Controller;


function match_conn(id: conn_id, reverse: bool): ofp_match
	{
	local dl_type = ETH_IPv4;
	local proto = IP_TCP;

	local orig_h: addr;
	local orig_p: port;
	local resp_h: addr;
	local resp_p: port;

	if ( reverse == F )
		{
		orig_h = id$orig_h;
		orig_p = id$orig_p;
		resp_h = id$resp_h;
		resp_p = id$resp_p;
		}
	else
		{
		orig_h = id$resp_h;
		orig_p = id$resp_p;
		resp_h = id$orig_h;
		resp_p = id$orig_p;
		}

		if ( is_v6_addr(orig_h) )
			dl_type = ETH_IPv6;

		if ( is_udp_port(orig_p) )
			proto = IP_UDP;
		else if ( is_icmp_port(orig_p) )
			proto = IP_ICMP;

		return ofp_match(
			$dl_type=dl_type,
			$nw_proto=proto,
			$nw_src=addr_to_subnet(orig_h),
			$tp_src=port_to_count(orig_p),
			$nw_dst=addr_to_subnet(resp_h),
			$tp_dst=port_to_count(resp_p)
		);
	}

# local function to forge a flow_mod cookie for this framework.
# all flow entries from the openflow framework should have the
# 42 bit of the cookie set.
function generate_cookie(cookie: count): count
	{
	local c = BRO_COOKIE_ID * COOKIE_BID_START;

	if ( cookie >= COOKIE_UID_SIZE )
		Reporter::warning(fmt("The given cookie uid '%d' is > 32bit and will be discarded", cookie));
	else
		c += cookie;

	return c;
	}

# local function to check if a given flow_mod cookie is forged from this framework.
function is_valid_cookie(cookie: count): bool
	{
	if ( cookie / COOKIE_BID_START == BRO_COOKIE_ID )
		return T;

	Reporter::warning(fmt("The given Openflow cookie '%d' is not valid", cookie));

	return F;
	}

function get_cookie_uid(cookie: count): count
	{
	if( is_valid_cookie(cookie) )
		return (cookie - ((cookie / COOKIE_GID_START) * COOKIE_GID_START));

	return INVALID_COOKIE;
	}

function get_cookie_gid(cookie: count): count
	{
	if( is_valid_cookie(cookie) )
		return (
			(cookie	- (COOKIE_BID_START * BRO_COOKIE_ID) -
			(cookie - ((cookie / COOKIE_GID_START) * COOKIE_GID_START))) /
			COOKIE_GID_START
		);

	return INVALID_COOKIE;
	}

function controller_init_done(controller: Controller)
	{
	if ( controller$state$_name !in name_to_controller )
		{
		Reporter::error(fmt("Openflow initialized unknown plugin %s successfully?", controller$state$_name));
		return;
		}

	controller$state$_activated = T;
	event OpenFlow::controller_activated(controller$state$_name, controller);
	}

# Functions that are called from cluster.bro and non-cluster.bro

function register_controller_impl(tpe: OpenFlow::Plugin, name: string, controller: Controller)
	{
	if ( controller$state$_name in name_to_controller )
		{
		Reporter::error(fmt("OpenFlow Controller %s was already registered. Ignored duplicate registration", controller$state$_name));
		return;
		}

	name_to_controller[controller$state$_name] = controller;

	if ( controller?$init )
		controller$init(controller$state);
	else
		controller_init_done(controller);
	}

function unregister_controller_impl(controller: Controller)
	{
	if ( controller$state$_name in name_to_controller )
		delete name_to_controller[controller$state$_name];
	else
		Reporter::error("OpenFlow Controller %s was not registered in unregister.");

	if ( controller?$destroy )
		controller$destroy(controller$state);
	}

function lookup_controller_impl(name: string): vector of Controller
	{
	if ( name in name_to_controller )
		return vector(name_to_controller[name]);
	else
		return vector();
	}
