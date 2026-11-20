use std::fmt;
use std::io;

#[derive(Debug)]
pub(crate) enum Error {
    StartThread(io::Error),
    AlreadySubscribed,
    Stopping,
    Stopped,
    CleanupUnconfirmed,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::StartThread(e) => write!(f, "Start the Nauvim engine thread: {e}"),
            Self::AlreadySubscribed => {
                f.write_str("The application already has an update subscriber")
            }
            Self::Stopping => f.write_str("The Nauvim engine is shutting down"),
            Self::Stopped => f.write_str("The Nauvim engine has stopped"),
            Self::CleanupUnconfirmed => {
                f.write_str("The Nauvim engine stopped before confirming its cleanup")
            }
        }
    }
}
