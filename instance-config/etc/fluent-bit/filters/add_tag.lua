--[[
--File: add_tag.lua
--File Created: Friday, 15th April 2022 2:39:12 pm
--Author: Josh.5 (jsunnex@gmail.com)
-------
--Last Modified: Wednesday, 12th July 2023 10:20:06 am
--Modified By: Josh.5 (jsunnex@gmail.com)
--]]


function append_tag(tag, timestamp, record)
    new_record = record
    new_record["tag"] = tag
    return 1, timestamp, new_record
end
