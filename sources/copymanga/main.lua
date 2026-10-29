return function(ctx)
    local source=ctx.require("contract").wrap(ctx,ctx.require("platform")(ctx))
    source.list_display={subtitle={"author"},details={"finished",{field="metadata.status"},
        {field="metadata.heat",label="热度"},"updated_at"}}
    return source
end
