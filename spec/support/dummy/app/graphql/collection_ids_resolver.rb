class CollectionIdsResolver

  def self.call(obj, _args, ctx)
    if obj.is_a?(OpenStruct)
      obj[ctx.field.name.gsub('_ids', '').pluralize]&.map(&:id)
    else
      obj.send(ctx.field.name)
    end
  end

end
