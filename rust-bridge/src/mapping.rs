use crate::protocol::StickFrame;

#[derive(Debug, Clone, Copy)]
pub struct XboxAxes {
    pub left_x: i16,
    pub left_y: i16,
    pub right_x: i16,
    pub right_y: i16,
}

fn normalize(value: u16) -> f32 {
    ((value as f32 - 1024.0) / 660.0).clamp(-1.0, 1.0)
}

fn axis(value: u16) -> i16 {
    (normalize(value) * i16::MAX as f32) as i16
}

pub fn mode2(frame: StickFrame) -> XboxAxes {
    XboxAxes {
        left_x: axis(frame.left_h),
        left_y: axis(frame.left_v),
        right_x: axis(frame.right_h),
        right_y: axis(frame.right_v),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn maps_verified_hardware_range() {
        let axes = mode2(StickFrame {
            right_h: 1684,
            right_v: 364,
            left_v: 1024,
            left_h: 1024,
        });
        assert!(axes.right_x > 32_000 && axes.right_y < -32_000 && axes.left_y == 0);
    }

    #[test]
    fn keeps_mode2_vertical_axes_on_their_source_sticks() {
        let axes = mode2(StickFrame {
            right_h: 1024,
            right_v: 1684,
            left_v: 364,
            left_h: 1684,
        });
        assert!(axes.left_x > 32_000 && axes.left_y < -32_000);
        assert!(axes.right_x == 0 && axes.right_y > 32_000);
    }
}
