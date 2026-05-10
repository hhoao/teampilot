import 'package:logger/logger.dart';

final appLogger = Logger(
  filter: DevelopmentFilter(),
  printer: PrettyPrinter(
    methodCount: 1,
    errorMethodCount: 3,
    lineLength: 80,
    colors: true,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.dateAndTime,
  ),
  output: ConsoleOutput(),
);
