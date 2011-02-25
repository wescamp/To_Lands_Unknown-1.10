--[=[
[animate_path]
Author: Alarantalara (username on the Battle for Wesnoth forum)

animate_path is a new tag that allows for movement of an object along paths not restricted by the hex grid

Required keys:
x,y: a sequence of points relative to the center of the reference hex in pixels through which the animation will travel
hex_x, hex_y: a hex on the map for which all other coordinates will be relative to
image: the image to display. It should have a 72 pixel transparent border surrounding it
frames: the number of frames to display in the movement
frame_length: the amount of time each frame will be visible

Optional keys:
linger: if yes, then leave the final frame visible
transpose: if yes, then the interpolation methods marked function will calculate based on y-values rather than x-values
interpolation: (default: linear) The method used to travel between points. Allowed values are: linear, bspline, parabola
Method Details:
    linear:
    bspline: requires that at least 4 points be specified
    parabola (function): requires exactly 3 points be specified - the x-values must be sorted (increasing or decreasing)

Example:
[animate_path]
    x=0,100,1000
    y=0,0,1000
    hex_x=10
    hex_y=10
    image=the_image.png
    frames=20
    frame_length=20
[/animate_path]

Note for those who want more options:
This file exposes a global table: interpolation_methods
You can add an initialization function to it to provide your own path function.
The initialization function receives a list of x values, a list of y values and the total number of locations
The number of x and y values are guaranteed to be the same

Your initialization function must return 3 functions:

The first function returns the length of each segment of the path, the number of segments and the total length of the path
It takes no parameters
<lengths>, num_lengths, total_length = length_function()
<lengths> must be an array indexed from [1..n] where n is the number of lengths
All lengths must be positive

The second function is called for each point of the path specified by the user
It takes one parameter specifying which segment in the path was reached (0..n where n is number of segments)
There are no return values

The third function is called containing the distance travelled along the current segment
This value will be in the range [0..length[segment_number]]
The function must return the absolute x,y coordinates of the associated point
x, y = get_point_on_current_segment_from_offset( offset )
]=]

local helper = wesnoth.require "lua/helper.lua"
local items = wesnoth.require "lua/wml/items.lua"

-- Linear Algebra
local epsilon = 0.0000000001

local function solve_system(A, b)
    -- solve a system of n equations in n unknowns
    -- A is a square matrix
    local size = #A
    for i = 1,size do
        -- find largest element as pivot
        local largest = i
        for j = i,size do
            if math.abs(A[largest][i]) < math.abs(A[j][i]) then
                largest = j
            end
        end
        -- swap if larger element found
        if math.abs(A[largest][i]) < epsilon then
            -- largest element remaining is 0, no unique solution
            return nil
        end
        if largest ~= i then
            A[i], A[largest] = A[largest], A[i]
            b[i], b[largest] = b[largest], b[i]
        end
        -- reduce
        for k = i+1,size do
            local m = A[k][i] / A[i][i]
            for j = i+1,size do
                A[k][j] = A[k][j] - m * A[i][j]
            end
            b[k] = b[k] - m * b[i]
        end
    end

    -- back substitute
    for i = size,1,-1 do
        for j = size,i+1,-1 do
            b[i] = b[i] - A[i][j] * b[j]
        end
        b[i] = b[i] / A[i][i]
    end
    return b
end

-- Image Placement Functions

local function place_image_offset(hex_x, hex_y, x, y, image)
    -- since halo doesn't have a key to offset an image, use the CROP
    -- function built into the wesnoth image placement to fake it
    -- requires a 72 pixel border around the image to work properly
    x = x*2
    y = y*2
    local w, h = wesnoth.get_image_size(image)

    w = w-math.abs(x)
    if w <= 0 then
        return
    end
    h = h-math.abs(y)
    if h <= 0 then
        return
    end
    if x > 0 then
        x = 0
    else
        x = -x
    end
    if y > 0 then
        y = 0
    else
        y = -y
    end
    image = string.format("%s~CROP(%d,%d,%d,%d)",image,x,y,w,h)
    items.place_halo(hex_x, hex_y, image)
    -- return the image name so it can removed non-destructively
    return image
end

local function calc_image_hex_offset(hex_x, hex_y, x, y)
    -- given a reference hex and an offset in pixels
    -- find the hex closest to the target and adjust the offset to be relative to that hex
    -- returns the new hex coordinates followed by the new pixel offset
    local hex_off_x = math.floor((x + 27) / 54)
    local k = 0
    if math.abs(hex_off_x) % 2 == 1 then
        if math.abs(hex_x) % 2 == 0 then
            k = 36
        else
            y = y - 36
        end
    end
    local hex_off_y = math.floor((y + 36) / 72)
    local new_x = x - hex_off_x * 54
    local new_y = y - (hex_off_y * 72) + k
    if new_y > 36 then
        new_y = new_y - 72
        hex_off_y = hex_off_y+1
    end

    return hex_x+hex_off_x, hex_y+hex_off_y, new_x, new_y
end

-- Miscellaneous Utilities

local function load_list(list)
    -- this loads a comma separated list into a 0-based array
    -- the 0 base simplifies later modular arithmetic
    local items = {}
    local num_items = 0
    for item in string.gmatch(list, "[^%s,][^,]*") do
        items[num_items] = item
        num_items = num_items + 1
    end
    return items, num_items
end

-- Interpolation Functions
interpolation_methods = {}

function interpolation_methods.linear( x_locs, y_locs, num_locs )
    -- encapsulates the linear interpolation algorithm
    local function calc_linear_path_length()
        if num_locs == 1 then
            return 0, 0
        end

        local total_length = 0
        local lengths = {}
        local last_x = x_locs[0]
        local last_y = y_locs[0]
        local cur_x, cur_y
        local num_lengths = 0
        for i = 1,num_locs-1 do
            cur_x = x_locs[i]
            cur_y = y_locs[i]
            lengths[i] = math.sqrt( (cur_x-last_x)^2 + (cur_y-last_y)^2 )
            total_length = total_length + lengths[i]
            last_x = cur_x
            last_y = cur_y
            num_lengths = num_lengths + 1
        end
        return lengths, num_lengths, total_length
    end

    local function reached_point(point)
        start_x = x_locs[point]
        start_y = y_locs[point]
        delta_x = x_locs[point+1] - start_x or 0
        delta_y = y_locs[point+1] - start_y or 0
    end

    local function get_location(offset)
        local x = (delta_x * offset) + start_x
        local y = (delta_y * offset) + start_y
        return x,y
    end

    local start_x, start_y
    local delta_x, delta_y

    return calc_linear_path_length, reached_point, get_location
end

function interpolation_methods.bspline( x_locs, y_locs, num_locs )
    -- implements uniform cubic B-splines
    local function calc_uniform_path_length()
        local lengths = {}
        for i = 1,num_locs-3 do
            lengths[i] = 1
        end
        return lengths, num_locs-3, num_locs-3
    end

    local function reached_point(point)
        index = point
    end

    local function get_location(offset)
        local u3 = offset*offset*offset
        local u2 = offset*offset
        local u  = offset
        local b0 = (-1*u3 + 3*u2 - 3*u + 1)
        local b1 = ( 3*u3 - 6*u2       + 4)
        local b2 = (-3*u3 + 3*u2 + 3*u + 1)
        local b3 = u3

        local x = b0*x_locs[index] + b1*x_locs[index+1] + b2*x_locs[index+2]
        local y = b0*y_locs[index] + b1*y_locs[index+1] + b2*y_locs[index+2]
        if index < num_locs-3 then
            x = x + b3*x_locs[index+3]
            y = y + b3*y_locs[index+3]
        end
        return x/6, y/6
    end

    if num_locs < 4 then
        helper.wml_error("[animate_path]: A B-spline path requires at least 4 points be specified")
    end
    local index

    return calc_uniform_path_length, reached_point, get_location
end

function interpolation_methods.parabola( x_locs, y_locs, num_locs )
    -- implements simple parabolas
    -- assumes that the parabola opens up or down and that the points are specified in
    -- either increasing or decreasing order (second assumption allows determination of direction of travel)
    if num_locs ~= 3 then
        helper.wml_error("[animate_path]: A parabola requires that exactly 3 points be specified")
    end
    local A, b, index
    A = {{x_locs[0]*x_locs[0], x_locs[0], 1},
         {x_locs[1]*x_locs[1], x_locs[1], 1},
         {x_locs[2]*x_locs[2], x_locs[2], 1}}
    b = {y_locs[0], y_locs[1], y_locs[2]} -- have to copy since input is 0-based
    b = solve_system(A, b)
    if b == nil then
        helper.wml_error("[animate_path]: The provided points do not form a parabola")
    end

    local function get_parabola_path_length()
        return {1},1,1
    end

    local function reached_point(point)
        index = point
    end

    local function get_location(offset)
        local x
        if index == 1 then
            x = x_locs[2]
        else
            x = offset*(x_locs[2] - x_locs[0]) + x_locs[0]
        end
        local y = b[1]*x*x + b[2]*x + b[3]
        return x, y
    end

    return get_parabola_path_length, reached_point, get_location
end

function wesnoth.wml_actions.animate_path(cfg)
    local hex_x = cfg.hex_x or helper.wml_error("Missing required hex_x= attribute in [animate_path]")
    local hex_y = cfg.hex_y or helper.wml_error("Missing required hex_y= attribute in [animate_path]")
    local frames = cfg.frames or helper.wml_error("Missing required frames= attribute in [animate_path]")
    if frames < 2 then
        helper.wml_error("[animate_path] requires frames be at least 2")
    end
    local delay = cfg.frame_length or helper.wml_error("Missing required frame_length= attribute in [animate_path]")
    local linger = cfg.linger
    local temp = cfg.image or helper.wml_error("[animate_path] missing required image= attribute")
    local images, num_images = load_list(temp)
    temp = cfg.x or helper.wml_error("[animate_path] missing required x= attribute")
    local x_locs, num_locs = load_list(temp)
    temp = cfg.y or helper.wml_error("[animate_path] missing required y= attribute")
    local y_locs, num_y_locs = load_list(temp)
    if num_locs ~= num_y_locs then
        helper.wml_error("The number of x and y values must be the same in [animate_path]")
    end
    local transpose = cfg.transpose

    local interpolation = cfg.interpolation or "linear"
    if not interpolation_methods[interpolation] then
        helper.wml_error("[animate_path]: Unknown interpolation method: "..interpolation)
    end
    if transpose then
        x_locs, y_locs = y_locs, x_locs
    end
    local calc_path_length, reached_point, get_location = interpolation_methods[interpolation]( x_locs, y_locs, num_locs )
    local lengths, num_lengths, total_length = calc_path_length()
    local length_seen = 0
    local next_point = 1
    -- subtract 1 from frames to avoid fencepost problems
    frames = frames - 1
    local length_per_frame = total_length / frames
    local x, y, target_hex_x, target_hex_y

    reached_point(0)
    for i = 0, frames do
        local cur_offset = i * length_per_frame - length_seen
        while next_point <= num_lengths and cur_offset > lengths[next_point] do
            reached_point(next_point)
            cur_offset = cur_offset - lengths[next_point]
            length_seen = length_seen + lengths[next_point]
            next_point = next_point + 1
        end
        if next_point <= num_lengths then
            cur_offset = cur_offset / lengths[next_point]
        else
            -- avoid rounding error at end of path
            cur_offset = 0
        end
        x, y = get_location(cur_offset)
        if transpose then
            x, y = y, x
        end
        target_hex_x, target_hex_y, x, y = calc_image_hex_offset(hex_x,hex_y,x,y)
        local image_name = place_image_offset( target_hex_x, target_hex_y, x, y, images[i%num_images])
        wesnoth.delay(delay)
        if i < frames or not linger then
            items.remove(target_hex_x, target_hex_y, image_name)
        end
    end
end