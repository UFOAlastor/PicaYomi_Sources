-- Strict GBK conversion without a platform iconv dependency. Never replace a
-- broken sequence silently: that would corrupt titles, searches or chapter text.
local map=require("gbk")
local C={}
local function utf8(cp)
    if cp<128 then return string.char(cp) end
    if cp<2048 then return string.char(192+math.floor(cp/64),128+cp%64) end
    return string.char(224+math.floor(cp/4096),128+math.floor(cp/64)%64,128+cp%64)
end
function C.decode(raw)
    assert(type(raw)=="string" and #raw<=2*1024*1024,"GBK input limit")
    local out,i={},1
    while i<=#raw do
        local a,b=raw:byte(i,i+1)
        if a<128 then out[#out+1]=string.char(a);i=i+1
        else
            assert(a>=129 and a<=254 and b and b>=64 and b<=254 and b~=127,"invalid GBK sequence")
            local at=((a-129)*190+b-64-(b>127 and 1 or 0))*4+1
            local cp=tonumber(map:sub(at,at+3),16)
            assert(cp and cp~=0,"unmapped GBK sequence")
            out[#out+1]=utf8(cp);i=i+2
        end
    end
    return table.concat(out)
end
function C.encode(text)
    assert(type(text)=="string" and #text<=4096,"GBK query limit")
    local out,i={},1
    while i<=#text do
        local a,b,c=text:byte(i,i+2)
        local cp,n
        if a<128 then cp,n=a,1
        elseif a>=194 and a<=223 and b and b>=128 and b<=191 then cp,n=(a-192)*64+b-128,2
        elseif a>=224 and a<=239 and b and b>=128 and b<=191 and c and c>=128 and c<=191 then
            cp,n=(a-224)*4096+(b-128)*64+c-128,3
            assert(cp>=2048 and (cp<55296 or cp>57343),"invalid UTF-8 sequence")
        else error("character is not supported by GBK") end
        if cp<128 then out[#out+1]=string.char(cp)
        else
            local needle=string.format("%04X",cp)
            local at=map:find(needle,1,true)
            while at and (at-1)%4~=0 do at=map:find(needle,at+1,true) end
            assert(at,"character is not supported by GBK")
            local cell=(at-1)/4
            local trail=cell%190+64
            if trail>=127 then trail=trail+1 end
            out[#out+1]=string.char(129+math.floor(cell/190),trail)
        end
        i=i+n
    end
    return table.concat(out)
end
return C
