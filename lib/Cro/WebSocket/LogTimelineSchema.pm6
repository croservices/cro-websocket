unit module Cro::WebSocket::LogTimelineSchema;

use Log::Timeline;

class Connected does Log::Timeline::Event['Cro::WebSocket', 'Client', 'Connected'] is export { }

class Sent does Log::Timeline::Task['Cro::WebSocket', 'Message', 'Sent'] is export { }

class Received does Log::Timeline::Task['Cro::WebSocket', 'Message', 'Received'] is export { }

