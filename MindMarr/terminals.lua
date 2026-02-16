-- MINDMARR Terminal Database
-- Add new entries here. C engine can request these by ID.

terminals = {
    [1] = {
        title = "LAB_LOG_01",
        is_corrupted = false,
        sanity_gain = 10,
        content = [[
Subject reports strange vibrations in the sub-floor. 
Initial scans show no seismic activity. 
It feels less like an earthquake and more like... 
a heartbeat.]]
    },

    [2] = {
        title = "SECURITY_FEED_SEC3",
        is_corrupted = true,
        sanity_gain = -5, -- Reading this HURTS your mind
        content = [[
ENTRY 404: 
Everything is red. 
Why is everyone so quiet? 
I tried to ask for help but I can only say it.
MINDMARR
MINDMARR
MINDMARR
MINDMARR]]
    },

    [3] = {
        title = "RECOVERY_PLANS",
        is_corrupted = false,
        sanity_gain = 15,
        content = [[
The escape shuttle is fueled. 
We just need the keycard from Sector 7. 
If you are reading this, don't listen to the wind. 
Keep your helmet sealed. Stay sane. You must not repeat what they say!]]
    },

        [4] = {
        title = "CAPTAIN'S_LOG",
        is_corrupted = true,
        sanity_gain = -5,
        content = [[
Captain's Log: 145
It was supposed to be a standard operation.
Then we began to hear the noises from down below, once we decoded
the signal we began to lose contact with different sectors quickly.
Once the radio began repeating itself from various people all saying the same word
it was followed by a silence, and an echoing name in the halls.
It appears they are trying to warn us or tell us about something called
Mindmarr.... miiinnnddddmmaaarrrr .... MiinDDMMAARRR MINDMAARRRRR 
Keep your helmet sealed. Stay sane. You must not repeat what they say!]]
    }
}

-- Simple helper function for your C backend to call
function get_terminal(id)
    return terminals[id] or nil
end