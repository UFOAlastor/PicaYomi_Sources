return function(ctx)
    return ctx.accounts.wrap(ctx.require("contract").wrap(ctx,ctx.require("init"),{legacy_order=true}))
end
