require "active_record_union/version"
require "active_record"
require "active_record_union/active_record/relation/set_ops"

module ActiveRecord
  class Relation
    include SetOps
  end
end
