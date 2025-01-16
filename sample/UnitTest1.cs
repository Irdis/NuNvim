namespace sample.abc.v1
{
    [TestFixture]
    public class Tests
    {
        [SetUp]
        public void Setup()
        {
        }

        [Test]
        public void Test1()
        {
            Assert.Pass();
        }
    }

    public class Tests2
    {
        [SetUp]
        public void Setup()
        {
        }

        public void Test1()
        {
            Assert.Pass();
        }
    }
}
