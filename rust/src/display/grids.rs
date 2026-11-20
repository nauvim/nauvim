use crate::api::display::{DisplayCell, DisplayGrid, DisplayRow};

use nvim_rpc_ui::{GridId, GridPlacementKind, State, Window};

use std::collections::BTreeMap;
use std::sync::Arc;

/// A normal window position read from Neovim when attachment events omit it.
pub(crate) struct WindowPosition {
    pub(crate) grid: GridId,
    pub(crate) window: Window,
    pub(crate) row: i64,
    pub(crate) col: i64,
}

pub(super) fn rows(state: &State, previous: Option<&State>) -> Vec<DisplayRow> {
    state
        .grids
        .iter()
        .filter(|(id, grid)| {
            previous
                .and_then(|s| s.grids.get(id))
                .is_none_or(|old| !Arc::ptr_eq(grid, old))
        })
        .flat_map(|(id, grid)| {
            let previous = previous
                .and_then(|s| s.grids.get(id))
                .filter(|g| g.width == grid.width && g.height == grid.height);
            grid.rows.iter().enumerate().filter_map(move |(row, data)| {
                if previous
                    .and_then(|g| g.rows.get(row))
                    .is_some_and(|old| Arc::ptr_eq(data, old))
                {
                    return None;
                }
                Some(DisplayRow {
                    grid: id.0,
                    row: u32::try_from(row).unwrap_or(u32::MAX),
                    cells: data
                        .cells
                        .iter()
                        .map(|c| DisplayCell {
                            text: c.text.to_string(),
                            highlight: c.highlight.0,
                        })
                        .collect(),
                })
            })
        })
        .collect()
}

pub(super) fn geometry(
    state: &State,
    positions: &BTreeMap<GridId, WindowPosition>,
) -> Vec<DisplayGrid> {
    state
        .grids
        .iter()
        .map(|(id, grid)| {
            let position = placement(state, *id, state.grids.len(), positions);
            let (row, col, zindex) = position.unwrap_or_default();
            DisplayGrid {
                id: id.0,
                width: u32::try_from(grid.width).unwrap_or(u32::MAX),
                height: u32::try_from(grid.height).unwrap_or(u32::MAX),
                row,
                col,
                zindex,
                order: state.placements.get(id).map_or(id.0, |p| match p.kind {
                    GridPlacementKind::Floating { compindex, .. }
                    | GridPlacementKind::Message { compindex, .. } => compindex.unwrap_or(id.0),
                    _ => id.0,
                }),
                hidden: position.is_none()
                    || state.placements.get(id).map_or_else(
                        || id.0 != 1 && restored(state, positions, *id).is_none(),
                        |p| p.hidden,
                    ),
            }
        })
        .collect()
}

pub(super) fn placement(
    state: &State,
    mut id: GridId,
    remaining: usize,
    positions: &BTreeMap<GridId, WindowPosition>,
) -> Option<(f64, f64, i64)> {
    let mut row = 0.;
    let mut col = 0.;
    let mut zindex = None;
    // An acyclic anchor chain visits at most one placement per retained grid.
    // Bounding the traversal also rejects cycles without recursive stack growth.
    for _ in 0..remaining {
        let grid = state.grids.get(&id)?;
        let Some(p) = state.placements.get(&id) else {
            if id.0 != 1
                && let Some(position) = restored(state, positions, id)
            {
                row += position.row as f64;
                col += position.col as f64;
            }
            return Some((row, col, zindex.unwrap_or(0)));
        };
        match &p.kind {
            GridPlacementKind::Normal { row: r, col: c, .. } => {
                return Some((row + *r as f64, col + *c as f64, zindex.unwrap_or(0)));
            }
            GridPlacementKind::Message {
                row: r, zindex: z, ..
            } => {
                return Some((row + *r as f64, col, zindex.unwrap_or(*z)));
            }
            GridPlacementKind::External { .. } => {
                return Some((row, col, zindex.unwrap_or(100)));
            }
            GridPlacementKind::Floating {
                anchor,
                anchor_grid,
                anchor_row,
                anchor_col,
                zindex: z,
                screen_row,
                screen_col,
                ..
            } => {
                let z = *zindex.get_or_insert(*z);
                if let (Some(r), Some(c)) = (screen_row, screen_col) {
                    return Some((row + *r as f64, col + *c as f64, z));
                }
                row += anchor_row;
                col += anchor_col;
                if anchor.starts_with('S') {
                    row -= grid.height as f64;
                }
                if anchor.ends_with('E') {
                    col -= grid.width as f64;
                }
                id = *anchor_grid;
            }
        }
    }
    None
}

fn restored<'a>(
    state: &State,
    positions: &'a BTreeMap<GridId, WindowPosition>,
    id: GridId,
) -> Option<&'a WindowPosition> {
    positions.get(&id).filter(|position| {
        state
            .viewports
            .get(&id)
            .is_some_and(|v| v.window == position.window)
    })
}
