import Foundation

/// The buddy's words (design decision 9): refusals said kindly, never an error code.
enum BuddyCopy {
    static func refusal(_ reason: String) -> String {
        switch reason {
        case "expired": "That code has expired. Ask your friend for a new one."
        case "used": "That code was already used."
        case "already_paired": "You already have a buddy."
        case "own_code": "That's your own code. Send it to a friend instead."
        case "unknown_code": "That code didn't work. Check it and try again."
        case "too_many_tries": "Too many tries. Try again in an hour."
        case "bad_name": "Use a name of 1 to 40 characters."
        case "no persistent store", "status_503": "Buddies aren't available right now."
        default: "Something went wrong. Try again."
        }
    }

    static let unreachable = "Couldn't reach Evergreen. Try again when you're online."
    static let invitePrompt = "Want a friend to cheer you on? Invite one"
}
