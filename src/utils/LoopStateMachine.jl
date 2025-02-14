"""
    LoopStateMachine

Utilities for returning state from functions that run inside a loop.

This is used in e.g clipping, where we may need to break or transition states.
"""
module LoopStateMachine

struct Action{name, T}
    x::T
end

Action{name}() where name = Action{name, Nothing}(nothing)
Action{name}(x::T) where name where T = new{name, T}(x)
Action(x::T) where T = Action{:unnamed, T}(x)

Action{name, Nothing}() where name = Action{name, Nothing}(nothing)

function Base.show(io::IO, action::Action{name, T}) where {name, T}
    print(io, "Action ", name)
    if isnothing(action.x)
        print(io, "()")
    else
        print(io, "(", action.x, ")")
    end
end


# Some common actions
"""
    Break()

Break out of the loop.
"""
const Break = Action{:Break, Nothing}

"""
    Continue()

Continue to the next iteration of the loop.
"""
const Continue = Action{:Continue, Nothing}

"""
    @processloopaction f(...)

Process the result of `f(...)` and return the result if it's not a `Continue` or `Break`.

If the result is a `Continue`, continue to the next iteration of the loop.

If the result is a `Break`, break out of the loop.

!!! warning
    Only use this inside a loop, otherwise you'll get a syntax error!
"""
macro processloopaction(expr)
    varname = gensym("lsm-f-ret")
    return quote
        $varname = $(esc(expr))
        if $varname isa Continue
            continue
        elseif $varname isa Break
            break
        else
            $varname
        end
    end
end

# You can define more actions as you desire.

end