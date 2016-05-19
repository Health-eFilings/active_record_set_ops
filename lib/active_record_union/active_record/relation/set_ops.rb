module ActiveRecord
  class Relation
    module SetOps
      SET_OPERATION_TO_AREL_CLASS = {
        union:     Arel::Nodes::Union,
        union_all: Arel::Nodes::UnionAll,
        intersect: Arel::Nodes::Intersect
      }.freeze

      def union(relation_or_where_arg, *args)
        set_operation(:union, relation_or_where_arg, *args)
      end

      def union_all(relation_or_where_arg, *args)
        set_operation(:union_all, relation_or_where_arg, *args)
      end

      def intersect(relation_or_where_arg, *args)
        set_operation(:intersect, relation_or_where_arg, *args)
      end

      private

      def set_operation(operation, relation_or_where_arg, *args)
        others = if relation_or_where_arg.is_a?(Relation)
                   [relation_or_where_arg, *args]
                 else
                   [@klass.where(relation_or_where_arg, *args)]
                 end

        verify_relations_for_set_operation!(operation, self, *others)

        # Postgres allows ORDER BY in the UNION subqueries if each subquery is
        # surrounded by parenthesis but SQLite does not allow parens around
        # the subqueries; you will have to explicitly do
        # `relation.reorder(nil)` in SQLite
        queries = if visitor.is_a?(Arel::Visitors::SQLite)
          [ast, *others.map(&:ast)]
        else
          [Arel::Nodes::Grouping.new(ast), *others.map(&:ast).map(&Arel::Nodes::Grouping.method(:new))]
        end

        arel_class = SET_OPERATION_TO_AREL_CLASS[operation]
        set = queries.reduce { |left, right| arel_class.new(left, right) }
        from = Arel::Nodes::TableAlias.new(
          set,
          @klass.quoted_table_name
        )

        relation = @klass.unscoped.from(from)
        relation.bind_values = arel.bind_values + bind_values +
                               others.map(&:arel).flat_map(&:bind_values) +
                               others.flat_map(&:bind_values)
        relation
      end

      def verify_relations_for_set_operation!(operation, *relations)
        includes_relations = relations.select { |r| r.includes_values.any? }

        if includes_relations.any?
          raise ArgumentError, "Cannot #{operation} relation with includes."
        end

        preload_relations = relations.select { |r| r.preload_values.any? }
        if preload_relations.any?
          raise ArgumentError, "Cannot #{operation} relation with preload."
        end

        eager_load_relations = relations.select { |r| r.eager_load_values.any? }
        if eager_load_relations.any?
          raise ArgumentError, "Cannot #{operation} relation with eager load."
        end
      end
    end
  end
end
