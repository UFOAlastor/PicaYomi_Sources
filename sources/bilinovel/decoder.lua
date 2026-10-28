-- Read the site's numeric paragraph-order parameters as data. No JavaScript
-- evaluation, browser, external descramble server or hard-coded chapter text.
local D={}
local function arithmetic(s)
    assert(type(s)=="string" and #s<=256,"expression limit")
    local pos,tokens=1,0
    local expression
    local function space() local _,last=s:find("^%s*",pos);pos=(last or pos-1)+1 end
    local function bounded(n)
        assert(n==n and math.abs(n)<=9007199254740991 and n%1==0,"invalid arithmetic result");return n
    end
    local function atom(depth)
        assert(depth<=16,"expression depth")
        space();tokens=tokens+1;assert(tokens<=128,"expression tokens")
        local c=s:sub(pos,pos)
        if c=="+" or c=="-" then pos=pos+1;local n=atom(depth+1);return c=="-" and -n or n end
        if c=="(" then
            pos=pos+1;local n=expression(depth+1);space();assert(s:sub(pos,pos)==")","missing bracket");pos=pos+1;return n
        end
        local token=s:match("^0[xX][%da-fA-F]+",pos) or s:match("^%d+",pos)
        assert(token,"only numeric expressions are accepted");pos=pos+#token;return bounded(assert(tonumber(token)))
    end
    local function product(depth)
        local n=atom(depth)
        while true do
            space();local op=s:sub(pos,pos)
            if op~="*" and op~="/" and op~="%" then return n end
            pos=pos+1;local rhs=atom(depth)
            if op=="*" then n=bounded(n*rhs)
            elseif op=="/" then assert(rhs~=0);n=bounded(n/rhs)
            else assert(rhs>0 and n>=0);n=bounded(n%rhs) end
        end
    end
    expression=function(depth)
        local n=product(depth)
        while true do
            space();local op=s:sub(pos,pos)
            if op~="+" and op~="-" then return n end
            pos=pos+1;local rhs=product(depth);n=bounded(op=="+" and n+rhs or n-rhs)
        end
    end
    local value=expression(0);space();assert(pos>#s,"unexpected expression suffix");return value
end
D.arithmetic=arithmetic
function D.parameters(js)
    assert(type(js)=="string" and #js<=262144,"script limit")
    local mul,offset=js:match("var%s+[%w_$]+%s*=%s*[^;]-Number%s*%(%s*[%w_$]+%s*%)%s*,%s*([^,)]+)%s*%)%s*,%s*([^,)]+)%s*%)%s*,")
    assert(mul and offset,"unknown chapter seed formula")
    local variable,a,c,mod=js:match("([%w_$]+)%s*=%s*[^;]-%(%s*%1%s*,%s*([^,)]+)%s*%)%s*,%s*([^,)]+)%s*%)%s*,%s*([^;)]+)%s*%)%s*;")
    assert(variable and a and c and mod,"unknown chapter shuffle formula")
    local fixed
    for _,value,_,second in js:gmatch("var%s+([%w_$]+)%s*=%s*([^;]+);function%s+[%w_$]+%s*%(([%w_$]+),([%w_$]+)%)") do
        if second==variable then assert(fixed==nil,"ambiguous fixed paragraphs");fixed=arithmetic(value) end
    end
    assert(fixed,"unknown fixed paragraph count")
    local p={fixed=fixed,mul=arithmetic(mul),offset=arithmetic(offset),a=arithmetic(a),c=arithmetic(c),mod=arithmetic(mod)}
    assert(p.fixed>=0 and p.fixed<=1000 and p.mul>0 and p.offset>=0 and p.a>0 and p.c>=0
        and p.mod>p.a and p.mod>p.c and p.a*p.mod+p.c<=9007199254740991,"invalid shuffle parameters")
    return p
end
function D.restore(body,cid,params)
    local paragraphs,slots={},{}
    for i,node in ipairs(body.nodes) do
        if node.name:lower()=="p" and node:getcontent():gsub("%s+","")~="" then
            paragraphs[#paragraphs+1]=node;slots[#slots+1]=i
        end
    end
    local n=#paragraphs
    assert(n<=10000,"paragraph limit")
    local indices,shuffled={},{}
    for i=1,n do if i<=params.fixed then indices[#indices+1]=i else shuffled[#shuffled+1]=i end end
    local seed=assert(tonumber(cid))*params.mul+params.offset
    assert(seed*params.a+params.c<=9007199254740991,"chapter seed limit")
    for i=#shuffled,2,-1 do
        seed=(seed*params.a+params.c)%params.mod
        local j=math.floor(seed/params.mod*i)+1
        shuffled[i],shuffled[j]=shuffled[j],shuffled[i]
    end
    for _,i in ipairs(shuffled) do indices[#indices+1]=i end
    local restored={}
    for i,node in ipairs(paragraphs) do restored[indices[i]]=node end
    local replacements={}
    for i,slot in ipairs(slots) do replacements[slot]=restored[i] end
    local out={}
    for i,node in ipairs(body.nodes) do
        node=replacements[i] or node
        local tag=node.name:lower()
        if tag=="p" or tag=="img" or tag=="br" or tag:match("^h[1-4]$") then
            out[#out+1]=node.root._text:sub(node._openstart,node._closeend)
        end
    end
    assert(#out>0,"empty chapter");return table.concat(out,"\n")
end
return D
