pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title Контракт с Хешированной Временной Блокировкой (HTLC)
 *
 * Этот контракт предоставляет способ создания и управления HTLC для ERC721 токенов.
 *
 * Смотрите HashedTimelock.sol для контракта, который предоставляет те же функции
 * для нативного ETH токена.
 *
 * Протокол:
 *
 *  1) newContract(receiver, hashlock, timelock, tokenContract, tokenId) - 
 *      отправитель вызывает это для создания нового HTLC для данного токена (tokenContract)
 *      для конкретного ID токена. Возвращается 32-байтный идентификатор контракта
 *  2) withdraw(contractId, preimage) - как только получатель узнает прообраз
 *      хеша блокировки, он может получить токены с помощью этой функции
 *  3) refund() - после истечения временной блокировки и если получатель не
 *      вывел токены, отправитель / создатель HTLC может вернуть свои токены
 *      с помощью этой функции.
 */
contract HashedTimelockBase {
    struct PaymentDetail {
        address tokenContract;     // адрес контракта токена для оплаты
        uint256 paymentAmount;     // сумма платежа
    }

    struct AssetDetail {
        address tokenContract;     // адрес контракта актива
        uint256 assetId;          // идентификатор актива
    }

    struct LockTrade {
        address sender;           // отправитель
        address receiver;         // получатель
        PaymentDetail payment;    // детали платежа
        AssetDetail asset;        // детали актива
        bytes32 hashlock;         // хеш блокировки
        uint256 timelock;         // временная блокировка
        bool withdrawn;           // выведено ли
        bool refunded;            // возвращено ли
        bytes32 preimage;         // прообраз
    }

    mapping(bytes32 => LockTrade) trades;

    modifier futureTimelock(uint256 _time) {
        // единственное требование - время блокировки должно быть после времени последнего блока (сейчас).
        // вероятно, вы захотите что-то немного дальше в будущем.
        // но это все еще полезная проверка:
        require(_time > block.timestamp, "время блокировки должно быть в будущем");
        _;
    }
    
    modifier tradeExists(bytes32 _tradeId) {
        require(haveTrade(_tradeId), "сделка с таким ID не существует");
        _;
    }
    
    modifier hashlockMatches(bytes32 _tradeId, bytes32 _x) {
        require(
            trades[_tradeId].hashlock == sha256(abi.encodePacked(_x)),
            "хеш блокировки не совпадает"
        );
        _;
    }
    
    modifier withdrawable(bytes32 _tradeId) {
        require(
            trades[_tradeId].receiver == msg.sender,
            "вывод доступен только получателю"
        );
        require(
            trades[_tradeId].withdrawn == false,
            "уже выведено"
        );
        // если мы хотим запретить вывод после истечения времени, раскомментируйте следующую строку
        // require(trades[_tradeId].timelock > now, "время блокировки должно быть в будущем");
        _;
    }
    
    modifier refundable(bytes32 _tradeId) {
        require(
            trades[_tradeId].sender == msg.sender,
            "возврат доступен только отправителю"
        );
        require(
            trades[_tradeId].refunded == false,
            "уже возвращено"
        );
        require(
            trades[_tradeId].withdrawn == false,
            "уже выведено"
        );
        require(
            trades[_tradeId].timelock <= block.timestamp,
            "время блокировки еще не истекло"
        );
        _;
    }

    /**
     * @dev Существует ли сделка с идентификатором _tradeId.
     * @param _tradeId Идентификатор в маппинге сделок.
     */
    function haveTrade(bytes32 _tradeId) internal view returns (bool exists) {
        exists = (trades[_tradeId].sender != address(0));
    }
}