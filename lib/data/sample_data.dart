import '../models/quiz.dart';

class SampleData {
  static List<QuizModule> get modules => [
        QuizModule(
          id: 'sample-1',
          name: '新一代信息技术',
          description: '86 题',
          days: [
            QuizDay(
              id: 'day-1',
              title: 'Day 1',
              questions: [
                Question(
                  id: 'q1',
                  type: QuestionType.choice,
                  content: '在计算机中，一个字节（Byte）由多少个二进制位组成？',
                  options: ['4 位', '8 位', '16 位', '32 位'],
                  answer: 1,
                ),
                Question(
                  id: 'q2',
                  type: QuestionType.choice,
                  content: '以下哪个是云计算的特点？',
                  options: ['需要购买硬件', '按需付费', '一次性投资大', '维护成本高'],
                  answer: 1,
                ),
                Question(
                  id: 'q3',
                  type: QuestionType.judge,
                  content: '物联网就是互联网。',
                  answer: false,
                ),
              ],
            ),
            QuizDay(
              id: 'day-2',
              title: 'Day 2',
              questions: [
                Question(
                  id: 'q4',
                  type: QuestionType.multi,
                  content: '以下哪些是大数据的特点？（选择两项）',
                  options: ['大量', '高速', '低速', '多样'],
                  answer: [0, 1],
                ),
                Question(
                  id: 'q5',
                  type: QuestionType.fill,
                  content: '大数据的4V特点包括______、高速、多样、低价值密度。',
                  answer: ['大量'],
                ),
              ],
            ),
          ],
        ),
        QuizModule(
          id: 'sample-2',
          name: '数据结构',
          description: '120 题',
          days: [
            QuizDay(
              id: 'day-3',
              title: 'Day 1',
              questions: [
                Question(
                  id: 'q6',
                  type: QuestionType.choice,
                  content: '栈的特点是什么？',
                  options: ['先进先出', '后进先出', '随机访问', '优先级'],
                  answer: 1,
                ),
              ],
            ),
          ],
        ),
      ];
}
