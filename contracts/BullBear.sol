// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Chainlink Imports
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// This import includes functions from both ./KeeperBase.sol and
// ./interfaces/KeeperCompatibleInterface.sol **Phase out, use
// AutomationCompatible to replace KeeperCompatibleInterface
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// Dev imports
//import "hardhat/console.sol";

contract BullBear is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, AutomationCompatible, VRFConsumerBaseV2 {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    AggregatorV3Interface public priceFeed;

    // VRF
    VRFCoordinatorV2Interface public COORDINATOR;
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    uint32 public callbackGasLimit = 500000; // set higher as fulfillRandomWords is doing a LOT of heavy lifting.
    uint64 public s_subscriptionId;
    bytes32 keyhash =  0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15; // keyhash, see for Goerli https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#goerli-testnet
    /**
    * Use an interval in seconds and a timestamp to slow execution of Upkeep
    */
    uint public /* immutable */ interval; 
    uint public lastTimeStamp;
    int256 public currentPrice;

    enum MarketTrend{BULL, BEAR} // Create Enum
    MarketTrend public currentMarketTrend = MarketTrend.BULL; 

    // IPFS URIs for the dynamic nft graphics/metadata.
    // NOTE: These connect to my IPFS Companion node.
    // You should upload the contents of the /ipfs folder to your own node for development.
    string[] bullUrisIpfs = [
        "https://ipfs.io/ipfs/QmRXyfi3oNZCubDxiVFre3kLZ8XeGt6pQsnAQRZ7akhSNs?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRJVFeMrtYS2CUVUM2cHJpBV5aX2xurpnsfZxLTTQbiD3?filename=party_bull.json",
        "https://ipfs.io/ipfs/QmdcURmN1kEEtKgnbkVJJ8hrmsSWHpZvLkRgsKKoiWvW9g?filename=simple_bull.json"
    ];
    string[] bearUrisIpfs = [
        "https://ipfs.io/ipfs/Qmdx9Hx7FCDZGExyjLR6vYcnutUR8KhBZBnZfAPHiUommN?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmTVLyTSuiKGUEmb88BgXG3qNC8YgpHZiFbjHrXKH3QHEu?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmbKhBXVWmwrYsTPFYfroR2N7NAekAMxHUVg2CWks7i9qj?filename=simple_bear.json"
    ];

    event TokenUpdated(string marketTrend);

    // For testing with the mock on Goerli, pass in 10(seconds) for `updateInterval` and the address of my 
    // deployed  MockPriceFeed.sol contract (0xD753A1c190091368EaC67bbF3Ee5bAEd265aC420).
    // Setup API price feed reference BTC/USD Goerli 0xA39434A63A52E749F02807ae27335515BA4b07F7
    // Setup VRF. Goerli VRF Coordinator 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
    constructor(uint updateInterval, address _priceFeed,  address _vrfCoordinator) ERC721("Bull&Bear", "BBTK") VRFConsumerBaseV2(_vrfCoordinator) {
        // Sets the keeper update interval
        interval = updateInterval;
        lastTimeStamp = block.timestamp; // seconds since unix epoch

        // set the price feed address to
        // BTC/USD Price Feed Contract Address on Goerli: https://goerli.etherscan.io/address/0xA39434A63A52E749F02807ae27335515BA4b07F7
        // or the MockPriceFeed Contract
        priceFeed = AggregatorV3Interface(_priceFeed); // To pass in the mock

        // set the price for the chosen currency pair.
        currentPrice = getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator); 
    }

    function safeMint(address to) public onlyOwner {
        // Current counter value will be the minted token's token ID.
        uint256 tokenId = _tokenIdCounter.current();

        // Increment it so next time it's correct when we call .current()
        _tokenIdCounter.increment();

        // Mint the token
        _safeMint(to, tokenId);

        // Defaults to gamer bull NFT image
        string memory defaultUri = bullUrisIpfs[0];
        _setTokenURI(tokenId, defaultUri);
    }

    function checkUpkeep(bytes calldata /*checkData*/) external view override returns(bool upkeepNeeded, bytes memory /*performData*/) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        // Recommended to revalidating the upkeep in the performUpkeep function
        if((block.timestamp - lastTimeStamp) > interval) {
            lastTimeStamp = block.timestamp;
            int latestPrice = getLatestPrice();

            if(latestPrice == currentPrice) {
                return;
            }

            if(latestPrice < currentPrice) {
                // bear
                currentMarketTrend = MarketTrend.BEAR;
            } else {
                // bull
                currentMarketTrend = MarketTrend.BULL;
            }

            // Initiate the VRF calls to get a random number (word)
            // that will then be used to to choose one of the URIs 
            // that gets applied to all minted tokens.
            requestRandomnessForNFTUris();

            currentPrice = latestPrice;
        } else {
            /*
            // interval not elapsed. No upkeep
            console.log(
                " INTERVAL NOT UP!");
            */
        }
        return;
    }

    // Helpers
    function getLatestPrice() public view returns (int256) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        

        return price; // example price returned 3034715771688 8 decimals
    }

    function requestRandomnessForNFTUris() internal {
        require(s_subscriptionId != 0, "Subscription ID not set");

        // Will revert if subscription Id is not set or funded
        s_requestId = COORDINATOR.requestRandomWords(
            keyhash, 
            s_subscriptionId, // See https://vrf.chain.link/
            3, //minimum confirmations before response
            callbackGasLimit,
            1 // `numWords` : number of random values we want. Max number for goerli is 500 (https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#goerli-testnet)
        ); // requestId looks like uint256: 80023009725525451140349768621743705773526822376835636211719588211198618496446
    }

    // This is the callback that the VRF coordinator sends the 
    // random values to.
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        // randomWords looks like this uint256: 68187645017388103597074813724954069904348581739269924188458647203960383435815
    
        string[] memory urisForTrend = currentMarketTrend == MarketTrend.BULL ? bullUrisIpfs : bearUrisIpfs;
        uint256 idx = randomWords[0] % urisForTrend.length; // use modulo to choose a random index.


        for (uint i = 0; i < _tokenIdCounter.current() ; i++) {
        _setTokenURI(i, urisForTrend[idx]);
        } 

        string memory trend = currentMarketTrend == MarketTrend.BULL ? "bullish" : "bearish";
    
        emit TokenUpdated(trend);
    }

    function setInterval(uint256 newInterval) public onlyOwner {
        interval = newInterval;
    }

    function setPriceFeed(address newFeed) public onlyOwner {
        priceFeed = AggregatorV3Interface(newFeed);
    }

    // For VRF Subscription Manager
    function setSubscriptionId(uint64 _id) public onlyOwner {
        s_subscriptionId = _id;
    }

    function setCallbackGasLimit(uint32 maxGas) public onlyOwner {
      callbackGasLimit = maxGas;
    }

    function setVrfCoodinator(address _address) public onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(_address);
    }

    /*
    // Helpers
    /// No longer used, replaced using enums
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }
    */

    /* 
    /// Remove logic and moved to fulfillRandomWords()
    function updateAllTokenUris(string memory trend) internal {
        if(compareStrings("bear", trend)) {
            for(uint i = 0; i < _tokenIdCounter.current(); i++) {
                _setTokenURI(i, bearUrisIpfs[0]);
            }
        } else {
            for(uint i = 0; i < _tokenIdCounter.current(); i++) {
                _setTokenURI(i, bullUrisIpfs[0]);
            }
        }

        emit TokenUpdated(trend);
    }
    */

    /* The following functions are overrides required by Solidity. */

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}