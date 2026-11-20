use std::num::NonZeroU32;

/// Positive Neovim grid counts, independent of logical window pixels.
#[derive(Clone, Copy)]
pub(super) struct GridSize {
    width: NonZeroU32,
    height: NonZeroU32,
}

impl GridSize {
    pub(super) fn new(width: u32, height: u32) -> Self {
        Self {
            width: NonZeroU32::new(width).unwrap_or(NonZeroU32::MIN),
            height: NonZeroU32::new(height).unwrap_or(NonZeroU32::MIN),
        }
    }

    pub(super) fn width(self) -> u32 {
        self.width.get()
    }

    pub(super) fn height(self) -> u32 {
        self.height.get()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_grid_counts_and_clamps_each_zero_dimension() {
        for (width, height, expected) in [
            (0, 0, (1, 1)),
            (0, 24, (1, 24)),
            (80, 0, (80, 1)),
            (80, 24, (80, 24)),
            (u32::MAX, u32::MAX, (u32::MAX, u32::MAX)),
        ] {
            let size = GridSize::new(width, height);

            assert_eq!((size.width(), size.height()), expected);
        }
    }
}
