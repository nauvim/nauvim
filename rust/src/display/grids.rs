use crate::api::display::{DisplayCell, DisplayGrid, DisplayRow};

use nvim_rpc_ui::{Grid, GridId, GridPlacementKind, Row, State, Window};

use std::collections::BTreeMap;
use std::sync::Arc;

const PRIMARY_GRID: GridId = GridId(1);

/// A normal window position read from Neovim when attachment events omit it.
pub(crate) struct WindowPosition {
    pub(crate) grid: GridId,
    pub(crate) window: Window,
    pub(crate) row: i64,
    pub(crate) col: i64,
}

#[derive(Default)]
pub(super) struct GridChanges {
    pub(super) rows: Vec<DisplayRow>,
    pub(super) removed: Vec<i64>,
}

pub(super) fn changes(state: &State, previous: Option<&State>) -> GridChanges {
    let mut changes = GridChanges::default();
    if previous.is_some_and(|old| Arc::ptr_eq(&state.grids, &old.grids)) {
        return changes;
    }

    // Both maps are ordered by grid ID. A single merge finds removed grids and
    // the previous rows for each retained grid.
    let mut old_grids = previous.into_iter().flat_map(|s| s.grids.iter()).peekable();
    for (&id, grid) in state.grids.iter() {
        while let Some((&removed, _)) = old_grids.next_if(|(old_id, _)| **old_id < id) {
            changes.removed.push(removed.0);
        }
        let old = old_grids
            .next_if(|(old_id, _)| **old_id == id)
            .map(|(_, g)| g);
        if old.is_some_and(|old| Arc::ptr_eq(grid, old)) {
            continue;
        }

        let rows = grid.rows.iter().enumerate();
        let project = |(row, data): (_, &Arc<Row>)| DisplayRow {
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
        };
        if let Some(old) = old.filter(|g| g.width == grid.width && g.height == grid.height) {
            let changed = rows
                .filter(|(row, data)| old.rows.get(*row).is_none_or(|old| !Arc::ptr_eq(data, old)));
            changes.rows.extend(changed.map(project));
        } else {
            changes.rows.extend(rows.map(project));
        }
    }
    changes.removed.extend(old_grids.map(|(id, _)| id.0));

    changes
}

pub(super) fn geometry(
    state: &State,
    positions: &mut BTreeMap<GridId, WindowPosition>,
) -> Vec<DisplayGrid> {
    positions.retain(|id, position| {
        state.grids.contains_key(id)
            && !state.placements.contains_key(id)
            && state
                .viewports
                .get(id)
                .is_some_and(|v| v.window == position.window)
    });

    state
        .grids
        .iter()
        .map(|(&id, grid)| {
            let (row, col, zindex, order, hidden) = if let Some(p) = state.placements.get(&id) {
                let (zindex, order) = match p.kind {
                    GridPlacementKind::Floating {
                        compindex, zindex, ..
                    }
                    | GridPlacementKind::Message {
                        compindex, zindex, ..
                    } => (zindex, compindex.unwrap_or(id.0)),
                    GridPlacementKind::External { .. } => (100, id.0),
                    GridPlacementKind::Normal { .. } => (0, id.0),
                };
                match placed_origin(state, grid, &p.kind, positions) {
                    Some((row, col)) => (row, col, zindex, order, p.hidden),
                    None => (0., 0., 0, order, true),
                }
            } else if let Some((row, col)) = restored_origin(positions, id) {
                (row, col, 0, id.0, false)
            } else {
                (0., 0., 0, id.0, id != PRIMARY_GRID)
            };
            DisplayGrid {
                id: id.0,
                width: u32::try_from(grid.width).unwrap_or(u32::MAX),
                height: u32::try_from(grid.height).unwrap_or(u32::MAX),
                row,
                col,
                zindex,
                order,
                hidden,
            }
        })
        .collect()
}

fn placed_origin<'a>(
    state: &'a State,
    mut grid: &'a Grid,
    mut kind: &'a GridPlacementKind,
    positions: &BTreeMap<GridId, WindowPosition>,
) -> Option<(f64, f64)> {
    let mut row = 0.;
    let mut col = 0.;
    // An acyclic anchor chain visits at most one placement per retained grid.
    // Bounding the traversal also rejects cycles without recursive stack growth.
    for _ in 0..state.grids.len() {
        match kind {
            GridPlacementKind::Normal { row: r, col: c, .. } => {
                return Some((row + *r as f64, col + *c as f64));
            }
            GridPlacementKind::Message { row: r, .. } => {
                return Some((row + *r as f64, col));
            }
            GridPlacementKind::External { .. } => {
                return Some((row, col));
            }
            GridPlacementKind::Floating {
                anchor,
                anchor_grid,
                anchor_row,
                anchor_col,
                screen_row,
                screen_col,
                ..
            } => {
                if let (Some(r), Some(c)) = (screen_row, screen_col) {
                    return Some((row + *r as f64, col + *c as f64));
                }
                row += anchor_row;
                col += anchor_col;
                if anchor.starts_with('S') {
                    row -= grid.height as f64;
                }
                if anchor.ends_with('E') {
                    col -= grid.width as f64;
                }
                grid = state.grids.get(anchor_grid)?;
                let Some(anchor) = state.placements.get(anchor_grid) else {
                    if let Some((r, c)) = restored_origin(positions, *anchor_grid) {
                        row += r;
                        col += c;
                    }
                    return Some((row, col));
                };
                kind = &anchor.kind;
            }
        }
    }
    None
}

fn restored_origin(positions: &BTreeMap<GridId, WindowPosition>, id: GridId) -> Option<(f64, f64)> {
    if id == PRIMARY_GRID {
        return None;
    }
    positions.get(&id).map(|p| (p.row as f64, p.col as f64))
}
