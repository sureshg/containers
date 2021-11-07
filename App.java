public class App {

  public static void main(String[] args) {
    System.out.println(args[0] + ": Java " + System.getProperty("java.version")
        + " running on "
        + System.getProperty("os.name")
        + " "
        + System.getProperty("os.arch")
    );
  }
}
