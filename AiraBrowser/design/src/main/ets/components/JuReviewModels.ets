/** 评价内容由宿主提供；示例数据应在板块标题或说明中明确标注。 */
export interface JuReview {
  key: string
  author: string
  title: string
  message: string
  rating: number
  avatar?: Resource
}
