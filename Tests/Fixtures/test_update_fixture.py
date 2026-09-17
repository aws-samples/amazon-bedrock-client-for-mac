import unittest
from unittest.mock import patch

from update_fixture import DownloadFixture


class DownloadFixtureTests(unittest.TestCase):
    def test_download_fixture_never_discovers_network_hosts(self):
        with patch("socket.getfqdn", side_effect=AssertionError("Unexpected hostname discovery")):
            with DownloadFixture() as server:
                self.assertEqual(server.server_name, "127.0.0.1")
                self.assertEqual(server.server_address[0], "127.0.0.1")
                self.assertGreater(server.server_port, 0)


if __name__ == "__main__":
    unittest.main()
