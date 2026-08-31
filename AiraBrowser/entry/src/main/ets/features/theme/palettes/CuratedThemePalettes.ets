import { BrowserThemePalette } from '../BrowserThemePaletteModels';
import { buildDarkTokens, buildLightTokens } from './ThemePaletteTokenBuilder';

export const CURATED_THEME_PALETTES: BrowserThemePalette[] = [
  {
    id: 'aurora',
    title: '晨屿',
    subtitle: '海雾青光',
    previewColor: '#1AAE9F',
    light: buildLightTokens('#1AAE9F', '#062B27', '#EEF8F6', '#FFFFFF', '#E5F2EF', '#0D1F1D'),
    dark: buildDarkTokens('#55D6C8', '#071C1A', '#0B1515', '#111F1F', '#172A2A')
  },
  {
    id: 'sage',
    title: '竹影',
    subtitle: '静绿灰调',
    previewColor: '#6F8F72',
    light: buildLightTokens('#6F8F72', '#172316', '#F0F5EF', '#FFFFFF', '#E4ECE2', '#172016'),
    dark: buildDarkTokens('#A8C8A7', '#102012', '#101810', '#182218', '#202D20')
  },
  {
    id: 'cedar',
    title: '森息',
    subtitle: '深林呼吸',
    previewColor: '#2F7D5C',
    light: buildLightTokens('#2F7D5C', '#072317', '#EEF6F1', '#FFFFFF', '#E2EEE7', '#0B1F17'),
    dark: buildDarkTokens('#77C7A2', '#071B12', '#0B1711', '#111F18', '#182B21')
  },
  {
    id: 'lagoon',
    title: '潮镜',
    subtitle: '温蓝水面',
    previewColor: '#168EAA',
    light: buildLightTokens('#168EAA', '#042733', '#EEF7FA', '#FFFFFF', '#E1F0F4', '#091E24'),
    dark: buildDarkTokens('#63CCE3', '#061A20', '#09161A', '#101F24', '#162B31')
  },
  {
    id: 'glacier',
    title: '薄霁',
    subtitle: '浅蓝晴空',
    previewColor: '#4D8FD6',
    light: buildLightTokens('#4D8FD6', '#071C36', '#EFF5FC', '#FFFFFF', '#E3EDF8', '#0D1C2C'),
    dark: buildDarkTokens('#91BFFF', '#071529', '#0B121D', '#121B29', '#192638')
  },
  {
    id: 'indigo',
    title: '夜航',
    subtitle: '蓝紫航线',
    previewColor: '#5968D8',
    light: buildLightTokens('#5968D8', '#10143A', '#F1F2FC', '#FFFFFF', '#E5E8F7', '#15172A'),
    dark: buildDarkTokens('#9BA6FF', '#0D1130', '#0F1120', '#17192D', '#20233E')
  },
  {
    id: 'wisteria',
    title: '云藤',
    subtitle: '柔紫云隙',
    previewColor: '#8C6CCF',
    light: buildLightTokens('#8C6CCF', '#24113A', '#F5F1FB', '#FFFFFF', '#EDE6F6', '#21162E'),
    dark: buildDarkTokens('#C2A7F2', '#1B0F2B', '#16111E', '#211A2D', '#2E2440')
  },
  {
    id: 'rosewood',
    title: '绯页',
    subtitle: '低饱和红',
    previewColor: '#B35C73',
    light: buildLightTokens('#B35C73', '#351018', '#FAF0F3', '#FFFFFF', '#F2E3E8', '#2B151B'),
    dark: buildDarkTokens('#E99AAF', '#2A0F18', '#1B1014', '#28171D', '#39212A')
  },
  {
    id: 'terracotta',
    title: '暖砖',
    subtitle: '红棕余温',
    previewColor: '#B86A43',
    light: buildLightTokens('#B86A43', '#351707', '#FAF2EC', '#FFFFFF', '#F1E4DA', '#28180F'),
    dark: buildDarkTokens('#E9A37B', '#2A1308', '#1A120D', '#271A13', '#39251A')
  },
  {
    id: 'amber',
    title: '灯穗',
    subtitle: '金色暖影',
    previewColor: '#B98216',
    light: buildLightTokens('#B98216', '#2B1A02', '#F9F4EA', '#FFFFFF', '#EFE5D1', '#241A0A'),
    dark: buildDarkTokens('#E3B75A', '#261804', '#17130B', '#231C11', '#342916')
  },
  {
    id: 'moss',
    title: '苔径',
    subtitle: '橄榄小路',
    previewColor: '#7A8A3A',
    light: buildLightTokens('#7A8A3A', '#20250A', '#F3F5EB', '#FFFFFF', '#E9ECD7', '#1B1F10'),
    dark: buildDarkTokens('#B9C875', '#1B2108', '#14170D', '#1F2314', '#2C331A')
  },
  {
    id: 'cyan',
    title: '晴瓷',
    subtitle: '清透青蓝',
    previewColor: '#1CA7B8',
    light: buildLightTokens('#1CA7B8', '#042C32', '#EEF8FA', '#FFFFFF', '#DFF1F4', '#071F24'),
    dark: buildDarkTokens('#69DCE9', '#061D21', '#081618', '#102225', '#173035')
  },
  {
    id: 'steel',
    title: '雾钢',
    subtitle: '理性灰蓝',
    previewColor: '#647D9A',
    light: buildLightTokens('#647D9A', '#101D2A', '#F0F4F8', '#FFFFFF', '#E4EAF0', '#141C25'),
    dark: buildDarkTokens('#A8BED8', '#101A26', '#10151B', '#19212A', '#242E3A')
  },
  {
    id: 'plum',
    title: '暮梅',
    subtitle: '深紫红晕',
    previewColor: '#8E5A89',
    light: buildLightTokens('#8E5A89', '#2B1230', '#F7F0F7', '#FFFFFF', '#EEE2EE', '#251625'),
    dark: buildDarkTokens('#D09ACC', '#241128', '#181018', '#241A25', '#342437')
  },
  {
    id: 'coral',
    title: '橙潮',
    subtitle: '柔亮橙粉',
    previewColor: '#D36559',
    light: buildLightTokens('#D36559', '#3A100B', '#FCF0EF', '#FFFFFF', '#F4E2DF', '#2C1512'),
    dark: buildDarkTokens('#F29B91', '#2E100C', '#1C100E', '#2A1714', '#3D211D')
  }
];
