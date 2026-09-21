use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StickFrame {
    pub right_h: u16,
    pub right_v: u16,
    pub left_v: u16,
    pub left_h: u16,
}

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("invalid DuML packet")]
    InvalidPacket,
}

pub fn crc8(data: &[u8]) -> u8 {
    let mut crc = 0x77u8;
    for byte in data {
        crc ^= byte;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0x8c
            } else {
                crc >> 1
            };
        }
    }
    crc
}

pub fn crc16(data: &[u8]) -> u16 {
    let mut crc = 0x3692u16;
    for byte in data {
        crc ^= *byte as u16;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0x8408
            } else {
                crc >> 1
            };
        }
    }
    crc
}

pub fn build_duml(command_id: u8, payload: &[u8]) -> Vec<u8> {
    let length = 13 + payload.len();
    let mut packet = vec![0x55, length as u8, ((length >> 8) as u8) | 0x04];
    packet.push(crc8(&packet));
    packet.extend_from_slice(&[0x0a, 0x06, 0xeb, 0x34, 0x40, 0x06, command_id]);
    packet.extend_from_slice(payload);
    packet.extend_from_slice(&crc16(&packet).to_le_bytes());
    packet
}

pub fn enable_simulator() -> Vec<u8> {
    build_duml(0x24, &[0x01])
}
pub fn read_sticks() -> Vec<u8> {
    build_duml(0x01, &[])
}

pub fn parse_sticks(packet: &[u8]) -> Result<StickFrame, ProtocolError> {
    if packet.len() != 38 || packet.first() != Some(&0x55) {
        return Err(ProtocolError::InvalidPacket);
    }
    let length = (packet[1] as usize) | (((packet[2] as usize) & 0x03) << 8);
    if length != packet.len()
        || crc8(&packet[..3]) != packet[3]
        || crc16(&packet[..packet.len() - 2]).to_le_bytes() != packet[packet.len() - 2..]
    {
        return Err(ProtocolError::InvalidPacket);
    }
    let word = |offset| u16::from_le_bytes([packet[offset], packet[offset + 1]]);
    Ok(StickFrame {
        right_h: word(13),
        right_v: word(16),
        left_v: word(19),
        left_h: word(22),
    })
}

pub fn drain_frames(buffer: &mut Vec<u8>) -> Vec<Vec<u8>> {
    let mut frames = Vec::new();
    loop {
        let Some(start) = buffer.iter().position(|byte| *byte == 0x55) else {
            buffer.clear();
            break;
        };
        if start > 0 {
            buffer.drain(..start);
        }
        if buffer.len() < 4 {
            break;
        }
        let length = (buffer[1] as usize) | (((buffer[2] as usize) & 0x03) << 8);
        if !(13..=1024).contains(&length) {
            buffer.drain(..1);
            continue;
        }
        if buffer.len() < length {
            break;
        }
        let packet: Vec<_> = buffer.drain(..length).collect();
        if packet[3] == crc8(&packet[..3])
            && crc16(&packet[..packet.len() - 2]).to_le_bytes() == packet[packet.len() - 2..]
        {
            frames.push(packet);
        }
    }
    frames
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_requests_match_hardware_lengths() {
        assert_eq!(enable_simulator().len(), 14);
        assert_eq!(read_sticks().len(), 13);
    }
    #[test]
    fn parser_rejects_corrupt_frames() {
        let mut packet = vec![0x55, 38, 4, 0];
        packet[3] = crc8(&packet[..3]);
        packet.resize(38, 0);
        let crc = crc16(&packet[..36]);
        packet[36..].copy_from_slice(&crc.to_le_bytes());
        assert!(parse_sticks(&packet).is_ok());
        packet[37] ^= 1;
        assert!(parse_sticks(&packet).is_err());
    }
}
