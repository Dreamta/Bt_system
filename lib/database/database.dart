import 'package:bt_system/global.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:drift/native.dart';

part 'database.g.dart';

// 学生表 (存入时年级和存入年份固定，计算当前年级使用 注册年级+当前年份-注册年份)
@DataClassName('Student')
class Students extends Table {
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get registGrade => integer().customConstraint('NOT NULL')();
  IntColumn get registYear => integer().customConstraint('NOT NULL')();
  @override
  Set<Column> get primaryKey => {name, registGrade, registYear};
}

// 课程表
@DataClassName('Course')
class Courses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text().withLength(min: 10, max: 10)();
  TextColumn get dayOfWeek => text().withLength(min: 1, max: 3)();
  TextColumn get beginTime => text().withLength(min: 1, max: 50).nullable()();
  RealColumn get hour => real().nullable()();
  TextColumn get subject => text().withLength(min: 1, max: 50)();
  TextColumn get courseType => text().withLength(min: 1, max: 50)();
  TextColumn get teacher => text().withLength(min: 1, max: 50).customConstraint(
      'NOT NULL REFERENCES teachers(name) ON DELETE CASCADE')();
  IntColumn get grade => integer().customConstraint('NOT NULL')();
  IntColumn get compensation => integer().nullable()();
  // TextColumn get studentsNames => text().withLength(min: 1, max: 8)();
}

// 老师表
@DataClassName('Teacher')
class Teachers extends Table {
  TextColumn get name => text().withLength(min: 1, max: 50)();

  @override
  Set<Column> get primaryKey => {name};
}

// 学生-课程表
@DataClassName('Student_Course')
class StudentCourses extends Table {
  TextColumn get studentName => text().withLength(min: 1, max: 50)();
  IntColumn get registGrade => integer().customConstraint('NOT NULL')();
  IntColumn get registYear => integer().customConstraint('NOT NULL')();
  IntColumn get courseId => integer()
      .customConstraint('NOT NULL REFERENCES courses(id) ON DELETE CASCADE')();
  IntColumn get price => integer().nullable()();
  @override
  Set<Column> get primaryKey =>
      {studentName, registGrade, registYear, courseId};
  // Foreign key constraints
  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(student_name, regist_grade, regist_year) REFERENCES students(name, regist_grade, regist_year) ON DELETE CASCADE'
      ];
}

@DriftDatabase(tables: [Students, Courses, StudentCourses, Teachers])
class MyDatabase extends _$MyDatabase {
  MyDatabase() : super(_openConnection());
  // @override
  // Future<void> beforeOpen(
  //     QueryExecutor executor, OpeningDetails details) async {
  //   await executor.customStatement('PRAGMA foreign_keys = ON;');
  // }

  @override
  MigrationStrategy get migration => MigrationStrategy(
          // 在数据库第一次创建时调用
          onCreate: (Migrator m) {
        return m.createAll();
      },
          // 在数据库打开时调用
          onUpgrade: (Migrator m, int from, int to) async {
        if (from < to) {
          // 这里可以添加更新逻辑
        }
      }, beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      });

  //当前学年计算
  int studyYear =
      DateTime.now().month > 8 ? DateTime.now().year + 1 : DateTime.now().year;
  @override
  int get schemaVersion => 1;

  // 查找所有学生
  Future<List<Student>> getAllStudents() => select(students).get();

  // 查找所有老师
  Future<List<Teacher>> getAllTeachers() => select(teachers).get();

  // 查找所有课程
  Future<List<Course>> getAllCourses() => select(courses).get();

  // 根据姓名查找学生
  Future<List<Student>> findStudentsByName(String name) {
    return (select(students)..where((tbl) => tbl.name.equals(name))).get();
  }

  // 根据姓名查找老师
  Future<List<Teacher>> findTeachersByName(String name) {
    return (select(teachers)..where((tbl) => tbl.name.equals(name))).get();
  }

  // 根据年级查找学生
  Future<List<Student>> findStudentsByGrade(GRADE curGrade) {
    final query = select(students)
      ..where((tbl) => (
          // 注册年级 = 当前年级 - 注册年份 + 当前年份

          tbl.registGrade.equals((gradeToInt[curGrade] ?? 0) -
              (tbl.registYear as int) +
              Global.caculateStudyYear())));
    return query.get();
  }

  // 查找某学生上过的所有课程
  // Future<List<Course>> findCoursesByStudent(
  //     String name, GRADE registGrade, int registYear) async {
  //   final coursesIdInQuery = select(studentCourses)
  //     ..where((tbl) =>
  //         tbl.studentName.equals(name) &
  //         tbl.registGrade.equals(gradeToInt[registGrade]!) &
  //         tbl.registYear.equals(registYear))
  //     ..map((row) => row.courseId);
  //   Future<List<Course>> list = (select(courses)
  //         ..where((course) => course.id.isInQuery(coursesIdInQuery)))
  //       .get();
  //   return await list;
  // }

// 查找某学生上过的所有课程
  Future<List<Course>> findCoursesByStudent(
      String name, GRADE registGrade, int registYear) async {
    // 执行子查询
    final coursesIdQuery = select(studentCourses)
      ..where((tbl) =>
          tbl.studentName.equals(name) &
          tbl.registGrade.equals(gradeToInt[registGrade]!) &
          tbl.registYear.equals(registYear));

    final coursesIds = await coursesIdQuery.map((row) => row.courseId).get();
    print("Found course IDs: $coursesIds");

    // 如果 coursesIds 为空，返回空列表
    if (coursesIds.isEmpty) {
      return [];
    }

    // 执行主查询
    final result = await (select(courses)
          ..where((course) => course.id.isIn(coursesIds)))
        .get();

    print("Found courses: $result");
    return result;
  }

  // 查找某课程的所有学生
  Future<List<Student>> findStudentsByCourse(int courseId) {
    return (select(students)
          ..where((student) => student.name.isInQuery(
                select(studentCourses)
                  ..where((tbl) => tbl.courseId.equals(courseId))
                  ..map((row) => row.studentName),
              )))
        .get();
  }

  // 根据课程名字查找课程
  Future<List<Course>> findCoursesByName(String subject) {
    return (select(courses)..where((tbl) => tbl.subject.equals(subject))).get();
  }

  // 查找某老师上过的所有课程
  Future<List<Course>> findCoursesByTeacher(String teacherName) {
    return (select(courses)..where((tbl) => tbl.teacher.equals(teacherName)))
        .get();
  }

  // 根据时间范围查找课程
  Future<List<Course>> findCoursesByDateRange(
      String startDate, String endDate) {
    final query = select(courses)
      ..where((tbl) => tbl.date.isBetweenValues(startDate, endDate));
    return query.get();
  }

  // 查找某年级所有课程
  Future<List<Course>> findCoursesByGrade(GRADE grade) {
    final query = select(courses)
      ..where((tbl) => tbl.grade.equals(gradeToInt[grade]!));
    return query.get();
  }

// 查找某学生的所有老师
  Future<List<Teacher>> findTeachersByStudent(
      String studentName, int registGrade, int registYear) {
    return (select(teachers)
          ..where((teacher) => teacher.name.isInQuery(
                select(courses).join([
                  innerJoin(studentCourses,
                      studentCourses.courseId.equalsExp(courses.id)),
                ])
                  ..where(studentCourses.studentName.equals(studentName))
                  ..where(studentCourses.registGrade.equals(registGrade))
                  ..where(studentCourses.registYear.equals(registYear))
                  ..map((row) => row.readTable(courses).teacher),
              )))
        .get();
  }

  // 查找某老师的所有学生
  Future<List<Student>> findStudentsByTeacher(String teacherName) {
    return (select(students)
          ..where((student) => student.name.isInQuery(
                select(studentCourses).join([
                  innerJoin(
                      courses, courses.id.equalsExp(studentCourses.courseId)),
                ])
                  ..where(courses.teacher.equals(teacherName))
                  ..map((row) => row.readTable(studentCourses).studentName),
              )))
        .get();
  }

  // 增加学生
  Future addStudent(String name, GRADE curGrade) async {
    final existStudent = await (select(students)
          ..where((tbl) =>
              tbl.name.equals(name) &
              //  检测注册年级 = 注册年级 + 注册学年 - 当前学年
              tbl.registGrade.equals(gradeToInt[curGrade] ??
                  0 - (tbl.registYear as int) + Global.caculateStudyYear())))
        .getSingleOrNull();
    if (existStudent == null) {
      return into(students).insert(StudentsCompanion.insert(
        name: (name),
        registGrade: (gradeToInt[curGrade]!),
        registYear: (studyYear),
      ));
    } else {
      // TODO:弹窗
    }
  }

  // 增加老师
  Future addTeacher({required String name}) async {
    final existTeacher = await (select(teachers)
          ..where((tbl) => tbl.name.equals(name)))
        .getSingleOrNull();
    if (existTeacher == null) {
      final TeachersCompanion teacher = TeachersCompanion(name: Value(name));
      return await into(teachers).insert(teacher);
    } else {
      // 抛出错误信息
    }
  }

  // 增加课程
  Future<int> addCourse({
    required String date,
    required String dayOfWeek,
    required String subject,
    required String courseType,
    required String teacher,
    required GRADE grade,
    String? beginTime,
    double? hour,
  }) {
    return into(courses).insert(CoursesCompanion.insert(
      date: (date),
      dayOfWeek: (dayOfWeek),
      beginTime: Value(beginTime),
      hour: Value(hour),
      subject: (subject),
      courseType: (courseType),
      teacher: (teacher),
      grade: (gradeToInt[grade]!),
    ));
  }

  // 增加学生-课程关系
  Future<int> addStudentCourse(
      {required String studentName,
      required int registGrade,
      required int courseId,
      int? price}) {
    return into(studentCourses).insert(StudentCoursesCompanion.insert(
      studentName: (studentName),
      registGrade: (registGrade),
      registYear: (studyYear),
      courseId: (courseId),
      price: Value(price),
    ));
  }

  // 删除所有学生
  Future deleteAllStudents() async {
    await delete(students).go();
    return await _deleteOrphanCourses();
  }

  // 删除所有老师
  Future<int> deleteAllTeachers() {
    return delete(teachers).go();
  }

  // 删除所有课程
  Future<int> deleteAllCourses() {
    return delete(courses).go();
  }

  // 删除所有学生-课程关系
  Future deleteAllStudentCourses() async {
    await delete(studentCourses).go();
    return deleteAllCourses();
  }

  // 单独删除特定学生
  Future deleteStudent(String name, GRADE registGrade, int registYear) async {
    (delete(students)
          ..where((tbl) =>
              tbl.name.equals(name) &
              tbl.registGrade.equals(gradeToInt[registGrade]!) &
              tbl.registYear.equals(registYear)))
        .go();

    return await _deleteOrphanCourses();
  }

  // 单独删除特定老师
  Future<int> deleteTeacher(String name) async {
    return await (delete(teachers)..where((tbl) => tbl.name.equals(name))).go();
  }

  // 单独删除特定课程
  Future<int> deleteCourse(int id) {
    return (delete(courses)..where((tbl) => tbl.id.equals(id))).go();
  }

  // 单独删除特定学生-课程关系
  Future deleteStudentCourse(String studentName, GRADE registGrade,
      int registYear, int courseId) async {
    (delete(studentCourses)
          ..where((tbl) =>
              tbl.studentName.equals(studentName) &
              tbl.registGrade.equals(gradeToInt[registGrade]!) &
              tbl.registYear.equals(registYear) &
              tbl.courseId.equals(courseId)))
        .go();
  }

  // 删除没有学生的课程
  Future<void> _deleteOrphanCourses() async {
    final coursesList = await select(courses).get();

    for (final course in coursesList) {
      final studentCount = await (select(studentCourses)
            ..where((tbl) => tbl.courseId.equals(course.id)))
          .get()
          .then((value) => value.length);
      print(studentCount);
      if (studentCount == 0) {
        await deleteCourse(course.id);
      }
    }
  }
}

// // 链接数据库
// LazyDatabase _openConnection() {
//   return LazyDatabase(() async {
//     final dbFolder = await getApplicationDocumentsDirectory();
//     print(dbFolder.path);
//     final file = File(p.join(dbFolder.path, 'db.sqlite'));
//     return NativeDatabase(file, logStatements: true);
//   });
// }
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    final NativeDatabase db = NativeDatabase(file, logStatements: true);

    // // 确保外键约束启用
    // await db.ensureOpen(MyDatabase()); // 确保数据库连接打开
    // await db.executor.runCustom('PRAGMA foreign_keys = ON');

    return db;
  });
}



// 添加学生，老师，课程
// 查找所有学生，老师，课程
// 根据姓名查找学生或老师，根据年级查找学生
// 查找某学生上过什么课，查找某节课有哪些学生，根据课程名字查找课程
// 查找某老师上过哪些课

// 当某节课的上课学生数为0时，删除对应课程（删除学生后检查）
// 