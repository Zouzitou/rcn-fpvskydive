use crate::protocol::StickFrame;
use std::{fs, path::Path};

#[derive(Debug, Clone, Copy)]
pub struct XboxAxes {
    pub left_x: i16,
    pub left_y: i16,
    pub right_x: i16,
    pub right_y: i16,
}

#[derive(Debug, Clone, Copy)]
pub struct AxisConfig {
    pub invert: bool,
    pub deadzone: f32,
    pub trim: f32,
    pub saturation: f32,
    pub curve: f32,
}

impl Default for AxisConfig {
    fn default() -> Self {
        Self {
            invert: false,
            deadzone: 0.0,
            trim: 0.0,
            saturation: 1.0,
            curve: 1.0,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct MappingConfig {
    pub left_x: AxisConfig,
    pub left_y: AxisConfig,
    pub right_x: AxisConfig,
    pub right_y: AxisConfig,
}

impl Default for MappingConfig {
    fn default() -> Self {
        Self {
            left_x: AxisConfig::default(),
            left_y: AxisConfig::default(),
            right_x: AxisConfig::default(),
            right_y: AxisConfig::default(),
        }
    }
}

impl MappingConfig {
    pub fn load(path: &Path) -> Self {
        let mut config = Self::default();
        let Ok(contents) = fs::read_to_string(path) else {
            return config;
        };
        for line in contents.lines() {
            let line = line.split('#').next().unwrap_or_default().trim();
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let key = key.trim();
            let value = value.trim();
            let Some((axis_name, field)) = key.split_once('.') else {
                continue;
            };
            let Some(axis) = axis_mut(&mut config, axis_name) else {
                continue;
            };
            match field {
                "invert" => {
                    if let Ok(parsed) = value.parse::<bool>() {
                        axis.invert = parsed;
                    }
                }
                "deadzone" => set_float(value, &mut axis.deadzone, 0.0, 0.95),
                "trim" => set_float(value, &mut axis.trim, -1.0, 1.0),
                "saturation" => set_float(value, &mut axis.saturation, 0.05, 1.0),
                "curve" => set_float(value, &mut axis.curve, 0.1, 4.0),
                _ => {}
            }
        }
        config
    }
}

fn axis_mut<'a>(config: &'a mut MappingConfig, name: &str) -> Option<&'a mut AxisConfig> {
    match name {
        "left_x" => Some(&mut config.left_x),
        "left_y" => Some(&mut config.left_y),
        "right_x" => Some(&mut config.right_x),
        "right_y" => Some(&mut config.right_y),
        _ => None,
    }
}

fn set_float(value: &str, target: &mut f32, minimum: f32, maximum: f32) {
    if let Ok(parsed) = value.parse::<f32>() {
        if parsed.is_finite() {
            *target = parsed.clamp(minimum, maximum);
        }
    }
}

fn normalize(value: u16) -> f32 {
    ((value as f32 - 1024.0) / 660.0).clamp(-1.0, 1.0)
}

fn axis(value: u16, config: AxisConfig) -> i16 {
    let mut normalized = normalize(value) + config.trim;
    let sign = normalized.signum();
    let magnitude = normalized.abs();
    normalized = if magnitude <= config.deadzone {
        0.0
    } else {
        sign * ((magnitude - config.deadzone) / (1.0 - config.deadzone))
    };
    normalized = (normalized / config.saturation).clamp(-1.0, 1.0);
    normalized = normalized.signum() * normalized.abs().powf(config.curve);
    if config.invert {
        normalized = -normalized;
    }
    (normalized * i16::MAX as f32) as i16
}

pub fn mode2_with_config(frame: StickFrame, config: MappingConfig) -> XboxAxes {
    XboxAxes {
        left_x: axis(frame.left_h, config.left_x),
        left_y: axis(frame.left_v, config.left_y),
        right_x: axis(frame.right_h, config.right_x),
        right_y: axis(frame.right_v, config.right_y),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn maps_verified_hardware_range() {
        let axes = mode2_with_config(
            StickFrame {
                right_h: 1684,
                right_v: 364,
                left_v: 1024,
                left_h: 1024,
            },
            MappingConfig::default(),
        );
        assert!(axes.right_x > 32_000 && axes.right_y < -32_000 && axes.left_y == 0);
    }

    #[test]
    fn keeps_mode2_vertical_axes_on_their_source_sticks() {
        let axes = mode2_with_config(
            StickFrame {
                right_h: 1024,
                right_v: 1684,
                left_v: 364,
                left_h: 1684,
            },
            MappingConfig::default(),
        );
        assert!(axes.left_x > 32_000 && axes.left_y < -32_000);
        assert!(axes.right_x == 0 && axes.right_y > 32_000);
    }

    #[test]
    fn applies_deadzone_trim_and_inversion() {
        let mut config = MappingConfig::default();
        config.left_x.deadzone = 0.1;
        config.left_x.trim = 0.25;
        config.left_x.invert = true;
        let axes = mode2_with_config(
            StickFrame {
                right_h: 1024,
                right_v: 1024,
                left_v: 1024,
                left_h: 1024,
            },
            config,
        );
        assert!(axes.left_x < 0);
    }

    #[test]
    fn clamps_invalid_config_values_when_loading() {
        let path = std::env::temp_dir().join("rcn-mapping-config-test.conf");
        fs::write(
            &path,
            "left_x.deadzone=2\nleft_x.saturation=-1\nleft_x.curve=20\nleft_x.trim=0.25\n",
        )
        .unwrap();
        let config = MappingConfig::load(&path);
        let _ = fs::remove_file(path);
        assert_eq!(config.left_x.deadzone, 0.95);
        assert_eq!(config.left_x.saturation, 0.05);
        assert_eq!(config.left_x.curve, 4.0);
        assert_eq!(config.left_x.trim, 0.25);
    }
}
